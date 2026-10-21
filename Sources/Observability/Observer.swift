/// One field per component, bundling a named logger and tracer — ported from platform-go's
/// `observability.Observer`. Replaces holding a logger/tracer pair everywhere.
///
/// The closure form of `operation` is the primary API: it starts a span, installs its context as the
/// task-local for the body (so nested operations link automatically across `async`/`await`), runs the
/// body, and ends the span — no `defer op.end()` to forget.
///
/// The body runs on the caller's isolation (an actor, `@MainActor`, or nonisolated), the same way
/// `withTaskGroup` does, so it can touch actor state directly.
public protocol Observer: Sendable {
  var logger: any Logger { get }
  var tracer: any Tracer { get }

  /// Conformers implement this; callers use the overloads in the extension, which fill `isolation`
  /// with `#isolation`. Protocol requirements can't take default arguments, and the closure is
  /// labeled `body:` so those overloads can't silently become a recursive default witness.
  func operation<R>(
    name: String, isolation: isolated (any Actor)?,
    body: (any ObservedOperation) async throws -> R
  ) async rethrows -> R
  func begin(name: String) -> any ObservedOperation
}

extension Observer {
  /// Closure-scoped operation. `name` defaults to the calling function, mirroring platform-go's
  /// caller-name spans (via `#function` instead of stack-walking).
  @discardableResult
  public func operation<R>(
    _ name: String = #function, isolation: isolated (any Actor)? = #isolation,
    _ body: (any ObservedOperation) async throws -> R
  ) async rethrows -> R {
    try await operation(name: name, isolation: isolation, body: body)
  }

  /// Closure-scoped operation with an explicit name.
  @discardableResult
  public func operation<R>(
    name: String, isolation: isolated (any Actor)? = #isolation,
    _ body: (any ObservedOperation) async throws -> R
  ) async rethrows -> R {
    try await operation(name: name, isolation: isolation, body: body)
  }

  /// Manual escape hatch. The caller owns `end()`; task-local propagation to nested async work is
  /// *not* automatic here — prefer the closure form unless you genuinely can't express it.
  public func begin(_ name: String = #function) -> any ObservedOperation {
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
    // Scope the tracer to this component so its spans are grouped by component in Instruments (the
    // component rides the signpost category — see ``SignpostTracer/named(_:)``). No-op for backends
    // that can't carry it.
    self.tracer = tracer.named(name)
  }

  public func operation<R>(
    name: String, isolation: isolated (any Actor)?,
    body: (any ObservedOperation) async throws -> R
  ) async rethrows -> R {
    let span = tracer.startSpan(name)
    let op = LiveOperation(span: span, logger: logger.withSpan(span))
    return try await SpanContextStore.$current.withValue(span.context) {
      defer { op.end() }
      return try await body(op)
    }
  }

  public func begin(name: String) -> any ObservedOperation {
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
