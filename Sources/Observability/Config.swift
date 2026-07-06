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

  /// Flush-and-stop hook, mirroring ``DiagnosticsProvider/shutdown()``. The native pillars (OSLog,
  /// signposts, swift-metrics) hold nothing that needs draining, so this is a no-op today. It exists
  /// so a future buffered exporter (the `ObservabilityOTel` OTLP path) can flush pending spans/metrics
  /// on teardown without a breaking API change. Safe to `await` on any `Pillars`, including `.noop`.
  public func shutdown() async {}
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

  private enum CodingKeys: String, CodingKey {
    case serviceName, logging, tracing, metrics
  }

  /// Lenient decode: any missing key falls back to its default (the Swift analogue of Go decoding to
  /// zero values), so a partial Info.plist/JSON config still decodes.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.serviceName = try c.decodeIfPresent(String.self, forKey: .serviceName) ?? "platform-swift"
    self.logging = try c.decodeIfPresent(LoggingConfig.self, forKey: .logging) ?? .init()
    self.tracing = try c.decodeIfPresent(TracingConfig.self, forKey: .tracing) ?? .init()
    self.metrics = try c.decodeIfPresent(MetricsConfig.self, forKey: .metrics) ?? .init()
  }

  /// Constructs the pillars described by this config. Pure and synchronous; the caller wires the
  /// result into its components.
  public func bootstrap() -> Pillars {
    let subsystem = Bundle.main.bundleIdentifier ?? "platform-swift"

    let logger: any Logger
    switch logging.provider {
    case .osLog:
      logger = OSLogLogger(
        subsystem: logging.subsystem ?? subsystem, category: logging.category, name: serviceName)
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

  private enum CodingKeys: String, CodingKey {
    case provider, subsystem, category
  }

  /// Lenient decode: missing keys fall back to defaults.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .osLog
    self.subsystem = try c.decodeIfPresent(String.self, forKey: .subsystem)
    self.category = try c.decodeIfPresent(String.self, forKey: .category) ?? "observability"
  }
}

public struct TracingConfig: Codable, Sendable {
  public enum Provider: String, Codable, Sendable {
    case signpost
    case noop
  }

  public var provider: Provider
  public var subsystem: String?
  /// Fraction of traces to sample, in `[0, 1]`, ported from platform-go's `SpanCollectionProbability`
  /// (OTel `TraceIDRatioBased`). `1.0` samples everything. The native signpost backend ignores it (it
  /// always records); it's carried here so a future OTLP exporter can configure its sampler.
  public var sampleRatio: Double

  public init(provider: Provider = .signpost, subsystem: String? = nil, sampleRatio: Double = 1.0) {
    self.provider = provider
    self.subsystem = subsystem
    self.sampleRatio = sampleRatio
  }

  private enum CodingKeys: String, CodingKey {
    case provider, subsystem, sampleRatio
  }

  /// Lenient decode: missing keys fall back to defaults (so `{}` yields `sampleRatio == 1.0`).
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .signpost
    self.subsystem = try c.decodeIfPresent(String.self, forKey: .subsystem)
    self.sampleRatio = try c.decodeIfPresent(Double.self, forKey: .sampleRatio) ?? 1.0
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

  private enum CodingKeys: String, CodingKey {
    case provider
  }

  /// Lenient decode: missing keys fall back to defaults.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .swiftMetrics
  }
}
