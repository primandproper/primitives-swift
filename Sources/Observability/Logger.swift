import Foundation
import os

/// Structured logger, ported from platform-go's `logging.Logger`.
///
/// Value semantics: every `with*` returns a *new* logger carrying the added context, mirroring the
/// Go interface (which returns a fresh `Logger` from each `WithValue`/`WithName`). Conformers must be
/// `Sendable` so an `Observer` can hand the same base logger to any task.
public protocol Logger: Sendable {
  func info(_ message: String)
  func debug(_ message: String)
  func error(_ whatWasHappening: String, _ error: Error)

  func withName(_ name: String) -> any Logger
  func withValue(_ key: String, _ value: AttributeValue) -> any Logger
  func withValues(_ values: [String: AttributeValue]) -> any Logger
  func withError(_ error: Error) -> any Logger
  func withSpan(_ span: any Span) -> any Logger
}

extension Logger {
  /// Sugar over ``withValue(_:_:)`` accepting any ``AttributeRepresentable``.
  public func withValue(_ key: String, _ value: some AttributeRepresentable) -> any Logger {
    withValue(key, value.attributeValue)
  }

  /// Attaches `span.id`/`trace.id` from a span context. Shared by every conformer.
  public func withSpan(_ span: any Span) -> any Logger {
    withValues([
      Keys.spanID: .string(span.context.spanID),
      Keys.traceID: .string(span.context.traceID),
    ])
  }

  public func withValues(_ values: [String: AttributeValue]) -> any Logger {
    values.reduce(self as any Logger) { $0.withValue($1.key, $1.value) }
  }

  public func withError(_ error: Error) -> any Logger {
    withValue(Keys.error, String(describing: error))
  }
}

// MARK: - OSLog (default iOS backend)

/// Default logger: writes to the unified logging system via `os.Logger`, so output lands in
/// Console.app and `log` streams with no infrastructure. Accumulated fields are rendered inline since
/// `os.Logger` has no structured-metadata channel of its own.
public struct OSLogLogger: Logger {
  private let backing: os.Logger
  private let name: String
  private let fields: [String: String]

  public init(
    subsystem: String = Bundle.main.bundleIdentifier ?? "platform-swift",
    category: String = "observability",
    name: String = ""
  ) {
    self.backing = os.Logger(subsystem: subsystem, category: category)
    self.name = name
    self.fields = [:]
  }

  private init(backing: os.Logger, name: String, fields: [String: String]) {
    self.backing = backing
    self.name = name
    self.fields = fields
  }

  public func info(_ message: String) {
    backing.info("\(self.renderPublic(message), privacy: .public) \(self.renderFields(), privacy: .private)")
  }

  public func debug(_ message: String) {
    backing.debug("\(self.renderPublic(message), privacy: .public) \(self.renderFields(), privacy: .private)")
  }

  public func error(_ whatWasHappening: String, _ error: Error) {
    // The developer-supplied context stays public; the error value may carry PII, so it rides the
    // private channel alongside the accumulated fields.
    backing.error(
      "\(self.renderPublic(whatWasHappening), privacy: .public) \(self.renderFields(extra: "\(error)"), privacy: .private)"
    )
  }

  public func withName(_ name: String) -> any Logger {
    OSLogLogger(backing: backing, name: name, fields: fields)
  }

  public func withValue(_ key: String, _ value: AttributeValue) -> any Logger {
    var next = fields
    next[key] = value.rendered
    return OSLogLogger(backing: backing, name: name, fields: next)
  }

  /// The always-visible portion: logger name, the message, and the *keys* of the accumulated fields
  /// (never their values), so you can see the shape of a log line even when its values are redacted.
  func renderPublic(_ message: String) -> String {
    var parts: [String] = []
    if !name.isEmpty { parts.append("[\(name)]") }
    parts.append(message)
    if !fields.isEmpty {
      parts.append("{" + fields.keys.sorted().joined(separator: " ") + "}")
    }
    return parts.joined(separator: " ")
  }

  /// The redactable portion: full `key=value` pairs (plus any `extra` such as an error value). Rendered
  /// with `privacy: .private` so unified logging masks the values unless the reader is trusted.
  func renderFields(extra: String? = nil) -> String {
    var pairs = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    if let extra { pairs.append(extra) }
    return pairs.joined(separator: " ")
  }
}

// The swift-log interop logger (`SwiftLogLogger`) lives in the separate `ObservabilityLog` target so
// the core module carries no swift-log dependency when the native `.osLog` backend is used.

// MARK: - Noop

/// Discards everything. Used for tests and as the always-safe fallback.
public struct NoopLogger: Logger {
  public init() {}
  public func info(_ message: String) {}
  public func debug(_ message: String) {}
  public func error(_ whatWasHappening: String, _ error: Error) {}
  public func withName(_ name: String) -> any Logger { self }
  public func withValue(_ key: String, _ value: AttributeValue) -> any Logger { self }
  public func withValues(_ values: [String: AttributeValue]) -> any Logger { self }
  public func withError(_ error: Error) -> any Logger { self }
  public func withSpan(_ span: any Span) -> any Logger { self }
}
