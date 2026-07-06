import Metrics

/// The four instrument kinds, re-exported from `swift-metrics`. platform-go exposes eight
/// (Float64/Int64 × Counter/Gauge/UpDownCounter/Histogram); swift-metrics collapses these onto a
/// smaller, type-agnostic set, which is the idiomatic surface here.
public typealias MetricCounter = Metrics.Counter
public typealias MetricGauge = Metrics.Gauge
public typealias MetricHistogram = Metrics.Recorder
public typealias MetricTimer = Metrics.Timer

/// Vends instruments, ported from platform-go's `metrics.Provider`. swift-metrics routes every
/// instrument to the process-wide factory installed via `MetricsSystem.bootstrap`, so the *backend*
/// (OTel, statsd, noop, …) is chosen there; this protocol is the convenience surface over it.
public protocol MetricsProvider: Sendable {
  func counter(_ name: String, tags: [String: String]) -> MetricCounter
  func gauge(_ name: String, tags: [String: String]) -> MetricGauge
  func histogram(_ name: String, tags: [String: String]) -> MetricHistogram
  func timer(_ name: String, tags: [String: String]) -> MetricTimer
}

extension MetricsProvider {
  public func counter(_ name: String) -> MetricCounter { counter(name, tags: [:]) }
  public func gauge(_ name: String) -> MetricGauge { gauge(name, tags: [:]) }
  public func histogram(_ name: String) -> MetricHistogram { histogram(name, tags: [:]) }
  public func timer(_ name: String) -> MetricTimer { timer(name, tags: [:]) }
}

/// Default provider. Constructs swift-metrics instruments bound to the bootstrapped factory; until an
/// app calls `MetricsSystem.bootstrap`, swift-metrics' own default is a no-op, so this is safe to use
/// before any backend is wired.
public struct SwiftMetricsProvider: MetricsProvider {
  public init() {}

  public func counter(_ name: String, tags: [String: String]) -> MetricCounter {
    Counter(label: name, dimensions: Self.dimensions(tags))
  }

  public func gauge(_ name: String, tags: [String: String]) -> MetricGauge {
    Gauge(label: name, dimensions: Self.dimensions(tags))
  }

  public func histogram(_ name: String, tags: [String: String]) -> MetricHistogram {
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
  // Keep the OBS-02 fix (instruments bound to NOOPMetricsHandler, not the process-wide factory) while
  // adopting OBS-15's namespaced return types.
  public func counter(_ name: String, tags: [String: String]) -> MetricCounter {
    Counter(label: name, factory: NOOPMetricsHandler.instance)
  }
  public func gauge(_ name: String, tags: [String: String]) -> MetricGauge {
    Gauge(label: name, factory: NOOPMetricsHandler.instance)
  }
  public func histogram(_ name: String, tags: [String: String]) -> MetricHistogram {
    Recorder(label: name, factory: NOOPMetricsHandler.instance)
  }
  public func timer(_ name: String, tags: [String: String]) -> MetricTimer {
    Timer(label: name, factory: NOOPMetricsHandler.instance)
  }
}
