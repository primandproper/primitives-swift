import Observability

/// The stateful ``CircuitBreaker`` — the Swift port of platform-go's `baseImplementation`, which wrapped
/// `rubyist/circuitbreaker`.
///
/// **Why an actor.** The breaker's failure/success counts, its open/closed flag, and the instant it
/// opened are mutable state read and written from arbitrary concurrent callers. Go guarded them with a
/// mutex inside the library; the faithful, race-free Swift shape is an `actor`, which serializes every
/// access without an explicit lock and satisfies `Sendable` for free. That is what makes the
/// ``CircuitBreaker`` accessors `async`.
///
/// **State machine.** Standard closed → open → half-open → closed, derived (never stored) from a single
/// `openedAt` timestamp, exactly as the Go library computed state on the fly:
/// - **closed** (`openedAt == nil`): calls proceed; each ``recordFailure()`` re-evaluates the trip
///   condition — `sampleCount >= minimumSampleThreshold && errorRate >= errorRatePercentage/100` — over
///   the rolling window (see ``RollingWindow``). Note the percent-vs-fraction conversion: Go's config
///   carries a 0–100 percentage while the window yields a 0–1 fraction, a mismatch that was an actual
///   bug in the Go origin.
/// - **open** (within `resetTimeout` of `openedAt`): ``canProceed()`` is false; calls reject fast.
/// - **half-open** (past `resetTimeout`): ``canProceed()`` is true for a trial. A ``recordSuccess()``
///   closes the breaker and clears the window; a ``recordFailure()`` re-trips it (pushing `openedAt`
///   forward), matching how the Go library's `Success()`/`Fail()` behaved in the half-open state.
///
/// **Clock choice.** All elapsed-time and open-timeout logic uses a monotonic ``ContinuousClock``, not
/// wall-clock `Date`: a breaker must not spring open or shut because the device clock was corrected,
/// the user crossed a timezone, or NTP stepped time. `ContinuousClock` only ever moves forward.
///
/// **Reset timeout.** Go delegated the open→half-open delay to the library's *exponential* backoff (it
/// grew with each re-trip). The port uses a single configurable ``resetTimeout`` — a fixed delay is
/// plenty for a client, and the field is the seam to grow it later if a real need appears, rather than
/// building the backoff machinery up front.
public actor StandardCircuitBreaker: CircuitBreaker {
  /// Default rolling-window span (`rubyist`'s `DefaultWindowTime`).
  public static let defaultWindow: Duration = .seconds(10)
  /// Default number of buckets in the window (`rubyist`'s `DefaultWindowBuckets`).
  public static let defaultBucketCount = 10
  /// Default open→half-open delay. A Swift-side choice (Go used the library's exponential backoff).
  public static let defaultResetTimeout: Duration = .seconds(30)

  private enum State {
    case closed
    case open
    case halfOpen
  }

  /// The configured breaker name, surfaced on ``CircuitOpenError`` and used to prefix its metrics.
  public let name: String

  private let errorRateFraction: Double
  private let minimumSampleThreshold: Int
  private let resetTimeout: Duration
  private let bucketNanos: Int64

  private let clock = ContinuousClock()
  private let windowStart: ContinuousClock.Instant
  private var window: RollingWindow
  private var openedAt: ContinuousClock.Instant?

  private let logger: any Logger
  private let trippedCounter: Counter
  private let failedCounter: Counter
  private let resetCounter: Counter

  /// Creates a breaker.
  ///
  /// - Parameters:
  ///   - name: Names the breaker in logs, metrics, and ``CircuitOpenError``.
  ///   - errorRatePercentage: Trip threshold as a **percentage** (0–100), matching Go's config field.
  ///   - minimumSampleThreshold: Minimum windowed sample count before the rate is even considered.
  ///   - resetTimeout: How long to stay open before allowing a half-open trial.
  ///   - window: Total rolling-window span.
  ///   - bucketCount: Number of buckets the window is divided into.
  ///   - logger: Observability logger (defaults to no-op so the breaker is usable un-instrumented).
  ///   - metrics: Observability metrics provider (defaults to no-op).
  ///   - tags: Fixed metric tags — the port of Go's `WithMetricAttributes`, used by the partitioned
  ///     breaker to tag each per-key breaker (e.g. `["partition": "tenant-123"]`).
  public init(
    name: String,
    errorRatePercentage: Double,
    minimumSampleThreshold: UInt64,
    resetTimeout: Duration = StandardCircuitBreaker.defaultResetTimeout,
    window: Duration = StandardCircuitBreaker.defaultWindow,
    bucketCount: Int = StandardCircuitBreaker.defaultBucketCount,
    logger: any Logger = NoopLogger(),
    metrics: any MetricsProvider = NoopMetricsProvider(),
    tags: [String: String] = [:]
  ) {
    self.name = name
    self.errorRateFraction = errorRatePercentage / 100.0
    self.minimumSampleThreshold = Int(minimumSampleThreshold)
    self.resetTimeout = resetTimeout
    let buckets = max(1, bucketCount)
    self.bucketNanos = max(1, Self.nanoseconds(window / buckets))
    self.window = RollingWindow(bucketCount: buckets)
    self.windowStart = ContinuousClock().now
    self.logger = logger.withValue("circuit_breaker", name)
    self.trippedCounter = metrics.counter("\(name)_circuit_breaker_tripped", tags: tags)
    self.failedCounter = metrics.counter("\(name)_circuit_breaker_failed", tags: tags)
    self.resetCounter = metrics.counter("\(name)_circuit_breaker_reset", tags: tags)
  }

  public func canProceed() -> Bool {
    state(at: clock.now) != .open
  }

  public func recordSuccess() {
    let now = clock.now
    window.recordSuccess(at: bucketIndex(now))

    // A success during the half-open trial proves the dependency has recovered: close and forget the
    // stale error rate so it can't immediately re-trip.
    if state(at: now) == .halfOpen {
      openedAt = nil
      window.reset()
      resetCounter.increment()
      logger.debug("circuit breaker reset after successful trial")
    }
  }

  public func recordFailure() {
    let now = clock.now
    window.recordFailure(at: bucketIndex(now))
    failedCounter.increment()

    // A failure during the half-open trial proves the dependency is still down: re-trip immediately,
    // regardless of the windowed rate, matching how the Go library's Fail() re-opened in the half-open
    // state. Under production timings (resetTimeout > window) the samples that first tripped the breaker
    // have aged out of the rolling window by the time the trial runs, so the rate check alone can't reach
    // shouldTrip on a lone trial failure — the breaker would stay half-open and keep flooding a dead
    // dependency.
    if state(at: now) == .halfOpen {
      openedAt = now
      trippedCounter.increment()
      logger.info("circuit breaker re-tripped after failed trial")
      return
    }

    if shouldTrip(at: now) {
      openedAt = now
      trippedCounter.increment()
      logger.info("circuit breaker tripped")
    }
  }

  // MARK: - Internals

  private func state(at now: ContinuousClock.Instant) -> State {
    guard let openedAt else { return .closed }
    return openedAt.duration(to: now) >= resetTimeout ? .halfOpen : .open
  }

  /// Mirrors the Go `ShouldTrip`: enough recent samples *and* a windowed error rate at or above the
  /// configured fraction.
  private func shouldTrip(at now: ContinuousClock.Instant) -> Bool {
    let (failures, successes) = window.totals(at: bucketIndex(now))
    let total = failures + successes
    guard total >= minimumSampleThreshold, total > 0 else { return false }
    return Double(failures) / Double(total) >= errorRateFraction
  }

  private func bucketIndex(_ now: ContinuousClock.Instant) -> Int {
    Int(Self.nanoseconds(windowStart.duration(to: now)) / bucketNanos)
  }

  /// Whole nanoseconds in a duration — the unit the bucket math runs in. Sub-nanosecond resolution is
  /// truncated; negative durations can't occur here because ``ContinuousClock`` never moves backward.
  private static func nanoseconds(_ duration: Duration) -> Int64 {
    let (seconds, attoseconds) = duration.components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }
}
