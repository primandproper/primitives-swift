import os

/// An error wrapped with the human-readable context of what was happening when it occurred — the
/// Swift analogue of platform-go's `PrepareError` wrapping.
public struct ObservabilityError: Error, CustomStringConvertible {
  public let context: String
  public let underlying: Error

  public init(_ context: String, _ underlying: Error) {
    self.context = context
    self.underlying = underlying
  }

  public var description: String { "\(context): \(underlying)" }
}

/// The per-call observability bag returned inside `Observer.operation`, ported from platform-go's
/// `observability.Operation`.
///
/// The defining behavior: ``set(_:_:)`` records to **both** the active span and the running
/// (span-enriched) logger, so a single call lands in your traces and your logs at once.
public protocol Operation: AnyObject, Sendable {
  /// Record on both span and logger.
  @discardableResult func set(_ key: String, _ value: AttributeValue) -> any Operation
  @discardableResult func setValues(_ values: [String: AttributeValue]) -> any Operation
  /// Record on the span only.
  @discardableResult func spanOnly(_ key: String, _ value: AttributeValue) -> any Operation
  /// Record on the logger only.
  @discardableResult func logOnly(_ key: String, _ value: AttributeValue) -> any Operation

  var logger: any Logger { get }
  var span: any Span { get }

  /// Logs the error against this operation's context, records it on the span, and returns it wrapped
  /// with `description` for propagation.
  @discardableResult func error(_ error: Error, _ description: String) -> Error
  /// Note an outcome without propagating: logs (error if non-nil, else info) and records on the span.
  func acknowledge(_ error: Error?, _ description: String)

  /// Ends the underlying span. Called automatically by the closure form of `operation`.
  func end()
}

extension Operation {
  /// Scalar sugar over the `AttributeValue` requirements so `op.set(Keys.responseStatus, code)`
  /// (an `Int`) and `op.set("name", "abc")` (a `String` literal) work without an explicit case.
  @discardableResult public func set(_ key: String, _ value: some AttributeRepresentable) -> any Operation {
    set(key, value.attributeValue)
  }
  @discardableResult public func spanOnly(_ key: String, _ value: some AttributeRepresentable) -> any Operation {
    spanOnly(key, value.attributeValue)
  }
  @discardableResult public func logOnly(_ key: String, _ value: some AttributeRepresentable) -> any Operation {
    logOnly(key, value.attributeValue)
  }
}

/// Production operation. Holds the span and a logger that grows as values are set; the mutable logger
/// is guarded by a lock so the operation is safe to touch across suspension points.
public final class LiveOperation: Operation, @unchecked Sendable {
  public let span: any Span
  private let state: OSAllocatedUnfairLock<State>

  private struct State {
    var logger: any Logger
  }

  init(span: any Span, logger: any Logger) {
    self.span = span
    self.state = OSAllocatedUnfairLock(initialState: State(logger: logger))
  }

  public var logger: any Logger { state.withLock { $0.logger } }

  @discardableResult
  public func set(_ key: String, _ value: AttributeValue) -> any Operation {
    span.attach(key, value)
    // `AttributeValue` is `Sendable`, so it crosses into the lock's `@Sendable` closure directly and
    // the read-modify-write happens under a single acquisition — concurrent sets can no longer read
    // the base logger before either stores and silently drop one another's keys (the OBS-01 race).
    state.withLock { $0.logger = $0.logger.withValue(key, value) }
    return self
  }

  @discardableResult
  public func setValues(_ values: [String: AttributeValue]) -> any Operation {
    for (k, v) in values { span.attach(k, v) }
    state.withLock {
      for (k, v) in values { $0.logger = $0.logger.withValue(k, v) }
    }
    return self
  }

  @discardableResult
  public func spanOnly(_ key: String, _ value: AttributeValue) -> any Operation {
    span.attach(key, value)
    return self
  }

  @discardableResult
  public func logOnly(_ key: String, _ value: AttributeValue) -> any Operation {
    state.withLock { $0.logger = $0.logger.withValue(key, value) }
    return self
  }

  @discardableResult
  public func error(_ error: Error, _ description: String) -> Error {
    let logger = self.logger
    logger.error(description, error)
    span.recordError(description, error)
    return ObservabilityError(description, error)
  }

  public func acknowledge(_ error: Error?, _ description: String) {
    if let error {
      logger.error(description, error)
      span.recordError(description, error)
    } else {
      logger.info(description)
    }
  }

  public func end() {
    span.end()
  }
}
