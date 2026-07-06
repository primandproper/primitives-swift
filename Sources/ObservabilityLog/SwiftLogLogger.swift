import Logging
import Observability

/// Wraps a `swift-log` `Logging.Logger`, for apps already invested in the swift-log ecosystem. Fields
/// flow through as real swift-log metadata; the backend is whatever `LoggingSystem.bootstrap` selected.
///
/// This lives in the `ObservabilityLog` interop target (not core `Observability`) so that apps using the
/// native `.osLog` logger carry no swift-log dependency. Construct it directly and hand it to `Pillars`:
/// `Pillars(logger: SwiftLogLogger(label: "myapp"), tracer: ..., metrics: ...)`.
public struct SwiftLogLogger: Observability.Logger {
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

  public func withName(_ name: String) -> any Observability.Logger {
    var copy = backing
    copy[metadataKey: Keys.serviceName] = "\(name)"
    return SwiftLogLogger(backing: copy)
  }

  public func withValue(_ key: String, _ value: AttributeValue) -> any Observability.Logger {
    var copy = backing
    copy[metadataKey: key] = "\(value.rendered)"
    return SwiftLogLogger(backing: copy)
  }
}
