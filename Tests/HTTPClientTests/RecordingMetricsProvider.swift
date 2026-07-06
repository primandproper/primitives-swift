import Foundation
import Metrics
import Observability
import os

/// A ``MetricsProvider`` test double that captures every counter increment with its label and tags, so
/// the failure-path metrics (NET-26) can be asserted. The test target ships only ``NoopMetricsProvider``
/// (which swallows everything) and the `SpyMetricsFactory` in ObservabilityTests is `private`, so this is
/// the local recording double.
///
/// Only counters are recorded — gauges/histograms/timers route to swift-metrics' `NOOPMetricsHandler`,
/// mirroring how ``NoopMetricsProvider`` binds instruments so they never reach a bootstrapped backend.
final class RecordingMetricsProvider: MetricsProvider, @unchecked Sendable {
  /// A single recorded `counter(...).increment()` call, with the tags it carried.
  struct CounterEvent: Sendable, Equatable {
    let name: String
    let tags: [String: String]
  }

  private let events = OSAllocatedUnfairLock(initialState: [CounterEvent]())

  /// Every counter increment observed so far, in order.
  var counterEvents: [CounterEvent] { events.withLock { $0 } }

  /// Counter increments recorded against `name`.
  func counterEvents(named name: String) -> [CounterEvent] {
    counterEvents.filter { $0.name == name }
  }

  func counter(_ name: String, tags: [String: String]) -> MetricCounter {
    // Passing `dimensions` here flows the tags into the factory's `makeCounter(label:dimensions:)`, so the
    // recording handler sees exactly what the caller tagged.
    Counter(
      label: name, dimensions: tags.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
      factory: factory)
  }

  func gauge(_ name: String, tags: [String: String]) -> MetricGauge {
    Gauge(label: name, factory: NOOPMetricsHandler.instance)
  }

  func histogram(_ name: String, tags: [String: String]) -> MetricHistogram {
    Recorder(label: name, factory: NOOPMetricsHandler.instance)
  }

  func timer(_ name: String, tags: [String: String]) -> MetricTimer {
    Timer(label: name, factory: NOOPMetricsHandler.instance)
  }

  private lazy var factory = RecordingCounterFactory { [events] label, dimensions in
    let tags = Dictionary(dimensions, uniquingKeysWith: { first, _ in first })
    events.withLock { $0.append(CounterEvent(name: label, tags: tags)) }
  }
}

/// A `MetricsFactory` whose counters report their label + dimensions on every increment; other
/// instruments are noop.
private final class RecordingCounterFactory: MetricsFactory, @unchecked Sendable {
  private let onIncrement: @Sendable (String, [(String, String)]) -> Void

  init(_ onIncrement: @escaping @Sendable (String, [(String, String)]) -> Void) {
    self.onIncrement = onIncrement
  }

  func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
    RecordingCounterHandler { self.onIncrement(label, dimensions) }
  }

  func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
    NOOPMetricsHandler.instance
  }

  func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
    NOOPMetricsHandler.instance
  }

  func destroyCounter(_ handler: CounterHandler) {}
  func destroyRecorder(_ handler: RecorderHandler) {}
  func destroyTimer(_ handler: TimerHandler) {}
}

private final class RecordingCounterHandler: CounterHandler, @unchecked Sendable {
  private let onIncrement: @Sendable () -> Void

  init(_ onIncrement: @escaping @Sendable () -> Void) { self.onIncrement = onIncrement }

  func increment(by amount: Int64) { onIncrement() }
  func reset() {}
}
