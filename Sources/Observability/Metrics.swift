import Metrics

/// The four instrument kinds, re-exported from `swift-metrics`. platform-go exposes eight
/// (Float64/Int64 × Counter/Gauge/UpDownCounter/Histogram); swift-metrics collapses these onto a
/// smaller, type-agnostic set, which is the idiomatic surface here.
public typealias Counter = Metrics.Counter
public typealias Gauge = Metrics.Gauge
public typealias Histogram = Metrics.Recorder
public typealias MetricTimer = Metrics.Timer

/// Vends instruments, ported from platform-go's `metrics.Provider`. swift-metrics routes every
/// instrument to the process-wide factory installed via `MetricsSystem.bootstrap`, so the *backend*
/// (OTel, statsd, noop, …) is chosen there; this protocol is the convenience surface over it.
public protocol MetricsProvider: Sendable {
  func counter(_ name: String, tags: [String: String]) -> Counter
  func gauge(_ name: String, tags: [String: String]) -> Gauge
  func histogram(_ name: String, tags: [String: String]) -> Histogram
  func timer(_ name: String, tags: [String: String]) -> MetricTimer
}

extension MetricsProvider {
  public func counter(_ name: String) -> Counter { counter(name, tags: [:]) }
  public func gauge(_ name: String) -> Gauge { gauge(name, tags: [:]) }
  public func histogram(_ name: String) -> Histogram { histogram(name, tags: [:]) }
  public func timer(_ name: String) -> MetricTimer { timer(name, tags: [:]) }
}

/// Default provider. Constructs swift-metrics instruments bound to the bootstrapped factory; until an
/// app calls `MetricsSystem.bootstrap`, swift-metrics' own default is a no-op, so this is safe to use
/// before any backend is wired.
public struct SwiftMetricsProvider: MetricsProvider {
  public init() {}

  public func counter(_ name: String, tags: [String: String]) -> Counter {
    Counter(label: name, dimensions: Self.dimensions(tags))
  }

  public func gauge(_ name: String, tags: [String: String]) -> Gauge {
    Gauge(label: name, dimensions: Self.dimensions(tags))
  }

  public func histogram(_ name: String, tags: [String: String]) -> Histogram {
    Recorder(label: name, dimensions: Self.dimensions(tags), aggregate: true)
  }

  public func timer(_ name: String, tags: [String: String]) -> MetricTimer {
    Timer(label: name, dimensions: Self.dimensions(tags))
  }

  private static func dimensions(_ tags: [String: String]) -> [(String, String)] {
    tags.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }
}

/// Explicit no-op provider for tests. Instruments it returns are bound to swift-metrics' own
/// `NOOPMetricsHandler` rather than the process-wide factory, so they stay silent even after an app
/// calls `MetricsSystem.bootstrap` — a `.noop`-configured component never emits real metrics.
public struct NoopMetricsProvider: MetricsProvider {
  public init() {}
  public func counter(_ name: String, tags: [String: String]) -> Counter {
    Counter(label: name, factory: NOOPMetricsHandler.instance)
  }
  public func gauge(_ name: String, tags: [String: String]) -> Gauge {
    Gauge(label: name, factory: NOOPMetricsHandler.instance)
  }
  public func histogram(_ name: String, tags: [String: String]) -> Histogram {
    Recorder(label: name, factory: NOOPMetricsHandler.instance)
  }
  public func timer(_ name: String, tags: [String: String]) -> MetricTimer {
    Timer(label: name, factory: NOOPMetricsHandler.instance)
  }
}
