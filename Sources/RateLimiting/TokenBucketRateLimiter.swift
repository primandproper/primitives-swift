import Observability

/// A per-key token-bucket ``RateLimiter`` — the Swift port of platform-go's
/// `ratelimiting.inMemoryRateLimiter`, which wraps a `golang.org/x/time/rate.Limiter` per key in a
/// `sync.Map`.
///
/// **Why an actor.** Go guards the per-key limiter map with a `sync.Map` so it can be read and written
/// from arbitrary concurrent goroutines. The Swift analogue for mutable shared state under the same
/// access pattern is an `actor`, which serializes bucket reads/writes without an explicit lock and is
/// `Sendable` for free — the same move ``StandardCircuitBreaker`` makes for its rolling window.
///
/// **Algorithm.** A standard token bucket per key: a bucket starts full (`burstSize` tokens, matching
/// `rate.NewLimiter`'s immediately-available burst) and refills continuously at `requestsPerSecond`
/// tokens/second, capped at `burstSize`. ``allow(key:count:)`` lazily refills the bucket for the time
/// elapsed since it was last touched, then allows — and debits `count` tokens from — the bucket only if
/// it holds enough; a bucket that doesn't have enough tokens is left untouched (no partial debit),
/// mirroring `rate.Limiter.AllowN`'s all-or-nothing check.
///
/// **Clock choice.** Refill math is driven by an injected, generic ``Clock`` (default
/// ``ContinuousClock``) rather than wall-clock `Date`, exactly mirroring ``StandardCircuitBreaker``: a
/// monotonic clock can't be fooled by a corrected system clock, a timezone change, or an NTP step, and a
/// test can substitute a manual clock to assert refill behavior deterministically without sleeping in
/// real time. As with ``StandardCircuitBreaker``, the arithmetic assumes the injected clock is
/// forward-only (``ContinuousClock``'s guarantee).
public actor TokenBucketRateLimiter<C: Clock>: RateLimiter where C.Duration == Duration {
  private struct Bucket {
    var tokens: Double
    var lastRefill: C.Instant
  }

  private let requestsPerSecond: Double
  private let burstSize: Int
  private let clock: C
  private var buckets: [String: Bucket] = [:]

  private let logger: any Logger
  private let allowedCounter: MetricCounter
  private let rejectedCounter: MetricCounter

  /// Creates a limiter.
  ///
  /// - Parameters:
  ///   - requestsPerSecond: Steady-state refill rate, in tokens/second. Negative values are clamped to
  ///     `0` (never refills past the initial burst), matching Go's config never producing a negative
  ///     `rate.Limit` in practice.
  ///   - burstSize: Bucket capacity — the maximum tokens a key can accumulate, and the number of
  ///     operations allowed in an instantaneous burst. Negative values are clamped to `0`.
  ///   - clock: The monotonic ``Clock`` driving all refill math. Defaults to ``ContinuousClock``; tests
  ///     inject a manual clock to advance elapsed time without sleeping. Must be forward-only.
  ///   - logger: Observability logger, used to log a debug line on limit-exceeded (defaults to no-op).
  ///   - metrics: Observability metrics provider backing the `_allowed`/`_rejected` counters ported
  ///     from Go's `inMemoryName + "_allowed"`/`"_rejected"` (defaults to no-op).
  ///   - tags: Fixed metric tags applied to both counters.
  public init(
    requestsPerSecond: Double,
    burstSize: Int,
    clock: C = ContinuousClock(),
    logger: any Logger = NoopLogger(),
    metrics: any MetricsProvider = NoopMetricsProvider(),
    tags: [String: String] = [:]
  ) {
    self.requestsPerSecond = max(requestsPerSecond, 0)
    self.burstSize = max(burstSize, 0)
    self.clock = clock
    self.logger = logger.withValue("rate_limiter", "in_memory")
    self.allowedCounter = metrics.counter("in_memory_rate_limiter_allowed", tags: tags)
    self.rejectedCounter = metrics.counter("in_memory_rate_limiter_rejected", tags: tags)
  }

  /// Convenience initializer threading bootstrapped ``Pillars`` — the analogue of Go's
  /// `NewInMemoryRateLimiter(metricsProvider, requestsPerSec, burstSize)`.
  public init(
    requestsPerSecond: Double,
    burstSize: Int,
    clock: C = ContinuousClock(),
    pillars: Pillars
  ) {
    self.init(
      requestsPerSecond: requestsPerSecond,
      burstSize: burstSize,
      clock: clock,
      logger: pillars.logger,
      metrics: pillars.metrics)
  }

  public func allow(key: String, count: Int) -> Bool {
    guard count > 0 else { return true }

    let now = clock.now
    var bucket = buckets[key] ?? Bucket(tokens: Double(burstSize), lastRefill: now)
    refill(&bucket, at: now)

    let allowed = bucket.tokens >= Double(count)
    if allowed {
      bucket.tokens -= Double(count)
    }
    buckets[key] = bucket

    if allowed {
      allowedCounter.increment()
    } else {
      rejectedCounter.increment()
      logger.debug("rate limit exceeded for key \(key)")
    }

    return allowed
  }

  /// The tokens currently available to `key`, refilled up through now — a Swift-native inspection seam
  /// the Go interface never exposed (it only ever asked "allowed or not"), useful for surfacing
  /// "N requests remaining" to a caller or asserting refill behavior in tests.
  public func availableTokens(for key: String) -> Double {
    guard var bucket = buckets[key] else { return Double(burstSize) }
    refill(&bucket, at: clock.now)
    return bucket.tokens
  }

  /// Drops every per-key bucket — the Swift analogue of Go's `Close()`, which cleared the `sync.Map` so
  /// it didn't retain memory past shutdown. Unlike Go's `Close()` this isn't terminal: the limiter stays
  /// usable afterward and every key simply starts fresh at a full bucket, since a Swift actor has no
  /// "closed" state to enforce.
  public func reset() {
    buckets.removeAll()
  }

  private func refill(_ bucket: inout Bucket, at now: C.Instant) {
    let elapsedSeconds = Self.seconds(bucket.lastRefill.duration(to: now))
    if elapsedSeconds > 0 {
      bucket.tokens = min(Double(burstSize), bucket.tokens + elapsedSeconds * requestsPerSecond)
    }
    bucket.lastRefill = now
  }

  /// Fractional seconds in a duration — the unit the refill math runs in. Negative durations can't
  /// occur here because ``ContinuousClock`` (and any conforming clock, by contract) never moves
  /// backward.
  private static func seconds(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }
}
