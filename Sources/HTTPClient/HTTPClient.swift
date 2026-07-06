import CircuitBreaking
import Foundation
import Observability
import Retry

/// An instrumented `URLSession` wrapper, ported from platform-go's `httpclient` package.
///
/// **What the Go package does, and how this differs.** Go's `httpclient` builds an `*http.Client`
/// whose transport is optionally wrapped by `otelhttp` — the instrumentation lives *inside* the
/// transport, invisible to callers. `URLSession` has no equivalent pluggable round-tripper, so the
/// instrumentation moves up one level: each request runs inside an ``Observability/Observer``
/// `operation` (a span whose context propagates to nested async work via the task-local), with the
/// method/URI recorded on the way in, the status on the way out, and latency/count emitted as metrics.
/// This is the same three-pillar telemetry Go gets from `otelhttp`, expressed in the ported observer
/// API rather than a transport shim.
///
/// **Resilience it composes (Go's package does neither itself — these are the port's value-add).**
/// - An optional ``Retry/RetryPolicy`` wraps the transport call, so a flaky request is retried per the
///   policy's backoff. Retry fires on *thrown* transport errors, not on non-2xx statuses — a 4xx/5xx
///   is a successful round-trip that returns an ``HTTPResponse`` (matching Go's `Client.Do`).
/// - An injected ``CircuitBreaking/CircuitBreaker`` gates requests (defaulting to a
///   ``CircuitBreaking/NoopCircuitBreaker`` that never trips, so an un-configured client behaves as if
///   there were no breaker): an open breaker fails fast with ``HTTPClientError/circuitBroken``, and
///   *every* attempt re-checks the gate and records success/failure so repeated faults trip it. This is
///   the same async actor-backed breaker the rest of the platform shares (NET-10 unified the HTTP
///   client's formerly-separate synchronous breaker contract onto it).
///
/// The type is a `Sendable` value: `URLSession` and every injected dependency are `Sendable`, so an
/// `HTTPClient` can be shared across tasks and stored in `Sendable` aggregates without ceremony.
public struct HTTPClient: Sendable {
  /// Classifies a completed response's status code as a circuit-breaker *failure*. Returning `true`
  /// records ``CircuitBreaking/CircuitBreaker/recordFailure()`` for the attempt; `false` records
  /// ``CircuitBreaking/CircuitBreaker/recordSuccess()``.
  ///
  /// This is a breaking-only concern, orthogonal to what ``perform(_:)`` returns: a non-2xx is still a
  /// successful round-trip that yields an ``HTTPResponse`` (matching Go's `Client.Do`). Without this
  /// seam every `HTTPURLResponse` — a 100%-500s server included — would record breaker *success*, so
  /// the breaker could never trip on the most common failure mode.
  public typealias StatusFailureClassifier = @Sendable (Int) -> Bool

  /// Observability name for this component, feeding the observer's logger name and span names —
  /// mirrors the `o11yName` const convention used across the platform packages.
  public static let o11yName = "httpclient"

  /// The default status classifier: treats the gateway-fault trio (502/503/504) as breaker failures
  /// and everything else as success. Widen or narrow the policy by injecting your own closure.
  public static let defaultStatusFailureClassifier: StatusFailureClassifier = { status in
    status == 502 || status == 503 || status == 504
  }

  /// The underlying session. Exposed so callers can reach `URLSession`-specific affordances when they
  /// must; the wrapper's instrumentation only applies to requests made through ``perform(_:)``.
  public let session: URLSession

  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let retryPolicy: (any RetryPolicy)?
  private let circuitBreaker: any CircuitBreaker
  private let statusFailureClassifier: StatusFailureClassifier

  /// Primary initializer: inject an already-built session, observer, and metrics provider.
  ///
  /// This is the seam tests use — pass a `URLSession` backed by a `URLProtocol` stub and a
  /// ``Observability/RecordingObserver`` to exercise the client hermetically, with no network.
  public init(
    session: URLSession,
    observer: any Observer,
    metrics: any MetricsProvider,
    retryPolicy: (any RetryPolicy)? = nil,
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker(),
    statusFailureClassifier: @escaping StatusFailureClassifier = HTTPClient.defaultStatusFailureClassifier
  ) {
    self.session = session
    self.observer = observer
    self.metrics = metrics
    self.retryPolicy = retryPolicy
    self.circuitBreaker = circuitBreaker
    self.statusFailureClassifier = statusFailureClassifier
  }

  /// Convenience initializer building the session and observer from config + pillars — the analogue of
  /// Go's `ProvideHTTPClient(cfg)`.
  ///
  /// Honors ``HTTPClientConfig/enableTracing`` the way Go's flag selected the `otelhttp` transport:
  /// when it's `false`, spans are suppressed by backing the observer with a ``Observability/NoopTracer``
  /// while logging and metrics stay live. Defaults are applied first, so a zero-valued config is safe.
  public init(
    config: HTTPClientConfig = HTTPClientConfig(),
    pillars: Pillars,
    retryPolicy: (any RetryPolicy)? = nil,
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker(),
    statusFailureClassifier: @escaping StatusFailureClassifier = HTTPClient.defaultStatusFailureClassifier
  ) {
    let cfg = config.ensuringDefaults()
    let tracer: any Tracer = cfg.enableTracing ? pillars.tracer : NoopTracer()
    let observer = LiveObserver(name: HTTPClient.o11yName, logger: pillars.logger, tracer: tracer)
    self.init(
      session: cfg.buildSession(),
      observer: observer,
      metrics: pillars.metrics,
      retryPolicy: retryPolicy,
      circuitBreaker: circuitBreaker,
      statusFailureClassifier: statusFailureClassifier
    )
  }

  /// Performs `request`, instrumented and (if configured) retried and circuit-broken.
  ///
  /// Returns the ``HTTPResponse`` for *any* completed round-trip, including non-2xx — mirroring Go's
  /// `Client.Do`, where a 4xx/5xx is a result rather than an error. Throws only on a tripped breaker,
  /// a transport/protocol failure, or cancellation.
  ///
  /// **Cancellation.** The async `URLSession` call is cancellation-aware: cancelling the surrounding
  /// `Task` unwinds the request by throwing (a `URLError.cancelled`, or `CancellationError` from the
  /// retry loop's `Task.checkCancellation`). The error propagates rather than being swallowed, so the
  /// caller learns the work was cut short — the structured-concurrency analogue of Go's `ctx.Done()`.
  @discardableResult
  public func perform(_ request: URLRequest) async throws -> HTTPResponse {
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? ""
    let path = request.url?.path ?? ""

    return try await observer.operation(name: "HTTP \(method) \(path)") { op in
      op.set(Keys.requestMethod, method)
      op.set(Keys.requestURI, urlString)

      // The breaker gate is checked *per attempt* inside `performOnce`, not once here: with a retry
      // policy, a breaker that trips partway through the retries must fail the remaining attempts fast
      // rather than keep hammering a failing dependency.
      let attempt: @Sendable () async throws -> HTTPResponse = {
        try await performOnce(request, op: op, method: method)
      }

      if let retryPolicy {
        return try await retryPolicy.execute(attempt)
      }
      return try await attempt()
    }
  }

  /// Convenience: perform a plain GET against `url`.
  @discardableResult
  public func perform(_ url: URL) async throws -> HTTPResponse {
    try await perform(URLRequest(url: url))
  }

  /// A single transport attempt: run the request, record telemetry and breaker outcome, and map the
  /// result. Retried verbatim by the policy when one is configured.
  private func performOnce(
    _ request: URLRequest, op: any Observability.Operation, method: String
  ) async throws -> HTTPResponse {
    // Gate this attempt on the breaker. Rejecting here (rather than once before the retry loop) means a
    // breaker that trips mid-retry short-circuits the remaining attempts instead of re-hitting the
    // transport. Throw the sentinel raw so callers can `catch HTTPClientError.circuitBroken` the way Go
    // callers compare against `circuitbreaking.ErrCircuitBroken`.
    if await circuitBreaker.cannotProceed() {
      op.acknowledge(HTTPClientError.circuitBroken, "circuit breaker open; refusing request")
      throw HTTPClientError.circuitBroken
    }

    let start = DispatchTime.now()
    do {
      let (data, response) = try await session.data(for: request)

      guard let http = response as? HTTPURLResponse else {
        await circuitBreaker.recordFailure()
        op.acknowledge(HTTPClientError.nonHTTPResponse, "response was not an HTTP response")
        throw HTTPClientError.nonHTTPResponse
      }

      recordMetrics(method: method, status: http.statusCode, start: start)
      op.set(Keys.responseStatus, http.statusCode)
      // A completed round-trip still returns its ``HTTPResponse`` (non-2xx included), but for breaking
      // purposes a server-fault status must count against the breaker or it can never trip on the most
      // common failure mode. The classifier decides; the default flags 502/503/504.
      if statusFailureClassifier(http.statusCode) {
        await circuitBreaker.recordFailure()
      } else {
        await circuitBreaker.recordSuccess()
      }
      return HTTPResponse(http: http, body: data)
    } catch let error as HTTPClientError {
      // Already recorded above (the non-HTTP-response path); just propagate.
      throw error
    } catch {
      // Preserve cancellation unwrapped so the retry loop sees it as terminal (see Retry.isTerminal)
      // and short-circuits instead of sleeping and re-attempting a request the caller abandoned. A
      // cancellation is the caller abandoning the work, not a transport fault, so it must be checked
      // *before* `recordFailure()` — otherwise a burst of user cancellations could trip a healthy
      // breaker.
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        op.acknowledge(error, "HTTP request cancelled")
        throw error
      }
      await circuitBreaker.recordFailure()
      throw op.error(error, "HTTP request failed")
    }
  }

  private func recordMetrics(method: String, status: Int, start: DispatchTime) {
    let elapsedNanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
    let tags = ["method": method, "status": String(status)]
    metrics.timer("http.client.request.duration", tags: tags)
      .recordNanoseconds(Int64(min(elapsedNanos, UInt64(Int64.max))))
    metrics.counter("http.client.requests", tags: tags).increment()
  }
}
