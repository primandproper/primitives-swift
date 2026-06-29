/// One field per component, bundling a named logger and tracer — ported from platform-go's
/// `observability.Observer`. Replaces holding a logger/tracer pair everywhere.
///
/// The closure form of `operation` is the primary API: it starts a span, installs its context as the
/// task-local for the body (so nested operations link automatically across `async`/`await`), runs the
/// body, and ends the span — no `defer op.end()` to forget.
public protocol Observer: Sendable {
  var logger: any Logger { get }
  var tracer: any Tracer { get }

  func operation<R>(name: String, _ body: (any Operation) async throws -> R) async rethrows -> R
  func begin(name: String) -> any Operation
}

extension Observer {
  /// Closure-scoped operation. `name` defaults to the calling function, mirroring platform-go's
  /// caller-name spans (via `#function` instead of stack-walking).
  @discardableResult
  public func operation<R>(_ name: String = #function, _ body: (any Operation) async throws -> R)
    async rethrows -> R
  {
    try await operation(name: name, body)
  }

  /// Manual escape hatch. The caller owns `end()`; task-local propagation to nested async work is
  /// *not* automatic here — prefer the closure form unless you genuinely can't express it.
  public func begin(_ name: String = #function) -> any Operation {
    begin(name: name)
  }
}

/// Production observer.
public struct LiveObserver: Observer {
  public let name: String
  public let logger: any Logger
  public let tracer: any Tracer

  public init(name: String, logger: any Logger, tracer: any Tracer) {
    self.name = name
    self.logger = logger.withName(name)
    self.tracer = tracer
  }

  public func operation<R>(name: String, _ body: (any Operation) async throws -> R) async rethrows
    -> R
  {
    let span = tracer.startSpan(name)
    let op = LiveOperation(span: span, logger: logger.withSpan(span))
    return try await SpanContextStore.$current.withValue(span.context) {
      defer { op.end() }
      return try await body(op)
    }
  }

  public func begin(name: String) -> any Operation {
    let span = tracer.startSpan(name)
    return LiveOperation(span: span, logger: logger.withSpan(span))
  }
}

/// Builds the production observer from bootstrapped pillars. The name is applied to both logger and
/// the spans started through it.
public func makeObserver(_ name: String, _ pillars: Pillars) -> any Observer {
  LiveObserver(name: name, logger: pillars.logger, tracer: pillars.tracer)
}

/// Builds an observer backed by a recording test double. See ``RecordingObserver``.
public func recordingObserver(_ name: String) -> RecordingObserver {
  RecordingObserver(name: name)
}
