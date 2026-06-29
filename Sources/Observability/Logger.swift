import Foundation
import Logging
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
  func withValue(_ key: String, _ value: Any) -> any Logger
  func withValues(_ values: [String: Any]) -> any Logger
  func withError(_ error: Error) -> any Logger
  func withSpan(_ span: any Span) -> any Logger
}

extension Logger {
  /// Attaches `span.id`/`trace.id` from a span context. Shared by every conformer.
  public func withSpan(_ span: any Span) -> any Logger {
    withValues([
      Keys.spanID: span.context.spanID,
      Keys.traceID: span.context.traceID,
    ])
  }

  public func withValues(_ values: [String: Any]) -> any Logger {
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
    backing.info("\(self.render(message), privacy: .public)")
  }

  public func debug(_ message: String) {
    backing.debug("\(self.render(message), privacy: .public)")
  }

  public func error(_ whatWasHappening: String, _ error: Error) {
    backing.error("\(self.render("\(whatWasHappening): \(error)"), privacy: .public)")
  }

  public func withName(_ name: String) -> any Logger {
    OSLogLogger(backing: backing, name: name, fields: fields)
  }

  public func withValue(_ key: String, _ value: Any) -> any Logger {
    var next = fields
    next[key] = String(describing: value)
    return OSLogLogger(backing: backing, name: name, fields: next)
  }

  private func render(_ message: String) -> String {
    var parts: [String] = []
    if !name.isEmpty { parts.append("[\(name)]") }
    parts.append(message)
    if !fields.isEmpty {
      parts.append(
        fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    }
    return parts.joined(separator: " ")
  }
}

// MARK: - swift-log interop

/// Wraps a `swift-log` `Logging.Logger`, for apps already invested in the swift-log ecosystem. Fields
/// flow through as real swift-log metadata; the backend is whatever `LoggingSystem.bootstrap` selected.
public struct SwiftLogLogger: Logger {
  private var backing: Logging.Logger

  public init(label: String) {
    self.backing = Logging.Logger(label: label)
  }

  private init(backing: Logging.Logger) {
    self.backing = backing
  }

  public func info(_ message: String) { backing.info("\(message)") }
  public func debug(_ message: String) { backing.debug("\(message)") }
  public func error(_ whatWasHappening: String, _ error: Error) {
    backing.error("\(whatWasHappening)", metadata: [Keys.error: "\(error)"])
  }

  public func withName(_ name: String) -> any Logger {
    var copy = backing
    copy[metadataKey: Keys.serviceName] = "\(name)"
    return SwiftLogLogger(backing: copy)
  }

  public func withValue(_ key: String, _ value: Any) -> any Logger {
    var copy = backing
    copy[metadataKey: key] = "\(String(describing: value))"
    return SwiftLogLogger(backing: copy)
  }
}

// MARK: - Noop

/// Discards everything. Used for tests and as the always-safe fallback.
public struct NoopLogger: Logger {
  public init() {}
  public func info(_ message: String) {}
  public func debug(_ message: String) {}
  public func error(_ whatWasHappening: String, _ error: Error) {}
  public func withName(_ name: String) -> any Logger { self }
  public func withValue(_ key: String, _ value: Any) -> any Logger { self }
  public func withValues(_ values: [String: Any]) -> any Logger { self }
  public func withError(_ error: Error) -> any Logger { self }
  public func withSpan(_ span: any Span) -> any Logger { self }
}
