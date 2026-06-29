import Foundation

/// The three pillars, ported from platform-go's `observability.Pillars` (minus profiling, which on iOS
/// is MetricKit — see ``Diagnostics``). All members are `Sendable`, so `Pillars` can be shared freely.
public struct Pillars: Sendable {
  public let logger: any Logger
  public let tracer: any Tracer
  public let metrics: any MetricsProvider

  public init(logger: any Logger, tracer: any Tracer, metrics: any MetricsProvider) {
    self.logger = logger
    self.tracer = tracer
    self.metrics = metrics
  }

  /// Everything no-op. The always-safe fallback.
  public static var noop: Pillars {
    Pillars(logger: NoopLogger(), tracer: NoopTracer(), metrics: NoopMetricsProvider())
  }
}

/// Root configuration, ported from platform-go's `observability.Config`. Unlike Go's `env:`-tagged
/// structs, this is plain `Codable` Swift built in code or decoded from Info.plist/JSON — iOS apps
/// don't configure from the environment.
///
/// The OTel providers are intentionally absent from these enums: the `ObservabilityOTel` target
/// supplies its own builders so the core graph carries no OpenTelemetry dependency.
public struct ObservabilityConfig: Codable, Sendable {
  public var serviceName: String
  public var logging: LoggingConfig
  public var tracing: TracingConfig
  public var metrics: MetricsConfig

  public init(
    serviceName: String = "platform-swift",
    logging: LoggingConfig = .init(),
    tracing: TracingConfig = .init(),
    metrics: MetricsConfig = .init()
  ) {
    self.serviceName = serviceName
    self.logging = logging
    self.tracing = tracing
    self.metrics = metrics
  }

  /// Native, zero-infrastructure defaults: OSLog + signposts.
  public static var `default`: ObservabilityConfig { .init() }

  /// Constructs the pillars described by this config. Pure and synchronous; the caller wires the
  /// result into its components.
  public func bootstrap() -> Pillars {
    let subsystem = Bundle.main.bundleIdentifier ?? "platform-swift"

    let logger: any Logger
    switch logging.provider {
    case .osLog:
      logger = OSLogLogger(
        subsystem: logging.subsystem ?? subsystem, category: logging.category, name: serviceName)
    case .swiftLog:
      logger = SwiftLogLogger(label: serviceName)
    case .noop:
      logger = NoopLogger()
    }

    let tracer: any Tracer
    switch tracing.provider {
    case .signpost:
      tracer = SignpostTracer(subsystem: tracing.subsystem ?? subsystem)
    case .noop:
      tracer = NoopTracer()
    }

    let metricsProvider: any MetricsProvider
    switch metrics.provider {
    case .swiftMetrics:
      metricsProvider = SwiftMetricsProvider()
    case .noop:
      metricsProvider = NoopMetricsProvider()
    }

    return Pillars(logger: logger, tracer: tracer, metrics: metricsProvider)
  }
}

public struct LoggingConfig: Codable, Sendable {
  public enum Provider: String, Codable, Sendable {
    case osLog
    case swiftLog
    case noop
  }

  public var provider: Provider
  public var subsystem: String?
  public var category: String

  public init(
    provider: Provider = .osLog, subsystem: String? = nil, category: String = "observability"
  ) {
    self.provider = provider
    self.subsystem = subsystem
    self.category = category
  }
}

public struct TracingConfig: Codable, Sendable {
  public enum Provider: String, Codable, Sendable {
    case signpost
    case noop
  }

  public var provider: Provider
  public var subsystem: String?

  public init(provider: Provider = .signpost, subsystem: String? = nil) {
    self.provider = provider
    self.subsystem = subsystem
  }
}

public struct MetricsConfig: Codable, Sendable {
  public enum Provider: String, Codable, Sendable {
    case swiftMetrics
    case noop
  }

  public var provider: Provider

  public init(provider: Provider = .swiftMetrics) {
    self.provider = provider
  }
}
