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
/// - An optional ``CircuitBreaker`` gates requests: an open breaker fails fast with
///   ``HTTPClientError/circuitBroken``; each attempt records success/failure so repeated faults trip it.
///
/// The type is a `Sendable` value: `URLSession` and every injected dependency are `Sendable`, so an
/// `HTTPClient` can be shared across tasks and stored in `Sendable` aggregates without ceremony.
public struct HTTPClient: Sendable {
  /// Observability name for this component, feeding the observer's logger name and span names —
  /// mirrors the `o11yName` const convention used across the platform packages.
  public static let o11yName = "httpclient"

  /// The underlying session. Exposed so callers can reach `URLSession`-specific affordances when they
  /// must; the wrapper's instrumentation only applies to requests made through ``perform(_:)``.
  public let session: URLSession

  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let retryPolicy: (any RetryPolicy)?
  private let circuitBreaker: (any CircuitBreaker)?

  /// Primary initializer: inject an already-built session, observer, and metrics provider.
  ///
  /// This is the seam tests use — pass a `URLSession` backed by a `URLProtocol` stub and a
  /// ``Observability/RecordingObserver`` to exercise the client hermetically, with no network.
  public init(
    session: URLSession,
    observer: any Observer,
    metrics: any MetricsProvider,
    retryPolicy: (any RetryPolicy)? = nil,
    circuitBreaker: (any CircuitBreaker)? = nil
  ) {
    self.session = session
    self.observer = observer
    self.metrics = metrics
    self.retryPolicy = retryPolicy
    self.circuitBreaker = circuitBreaker
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
    circuitBreaker: (any CircuitBreaker)? = nil
  ) {
    let cfg = config.ensuringDefaults()
    let tracer: any Tracer = cfg.enableTracing ? pillars.tracer : NoopTracer()
    let observer = LiveObserver(name: HTTPClient.o11yName, logger: pillars.logger, tracer: tracer)
    self.init(
      session: cfg.buildSession(),
      observer: observer,
      metrics: pillars.metrics,
      retryPolicy: retryPolicy,
      circuitBreaker: circuitBreaker
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

      if let circuitBreaker, circuitBreaker.cannotProceed() {
        // Record + log, but throw the sentinel raw so callers can `catch HTTPClientError.circuitBroken`
        // the way Go callers compare against `circuitbreaking.ErrCircuitBroken`.
        op.acknowledge(HTTPClientError.circuitBroken, "circuit breaker open; refusing request")
        throw HTTPClientError.circuitBroken
      }

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
    let start = DispatchTime.now()
    do {
      let (data, response) = try await session.data(for: request)

      guard let http = response as? HTTPURLResponse else {
        circuitBreaker?.failed()
        op.acknowledge(HTTPClientError.nonHTTPResponse, "response was not an HTTP response")
        throw HTTPClientError.nonHTTPResponse
      }

      recordMetrics(method: method, status: http.statusCode, start: start)
      op.set(Keys.responseStatus, http.statusCode)
      circuitBreaker?.succeeded()
      return HTTPResponse(http: http, body: data)
    } catch let error as HTTPClientError {
      // Already recorded above (the non-HTTP-response path); just propagate.
      throw error
    } catch {
      circuitBreaker?.failed()
      // Preserve cancellation unwrapped so the retry loop sees it as terminal (see Retry.isTerminal)
      // and short-circuits instead of sleeping and re-attempting a request the caller abandoned.
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        op.acknowledge(error, "HTTP request cancelled")
        throw error
      }
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
