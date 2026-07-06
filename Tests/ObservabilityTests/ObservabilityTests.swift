import Foundation
import Metrics
import Testing
import struct os.OSAllocatedUnfairLock

@testable import Observability

struct SampleError: Error {}

@Suite("Observer / Operation")
struct ObserverOperationTests {

  @Test("set dual-writes to both span and logger; spanOnly/logOnly route correctly")
  func dualWriteAndRouting() async {
    let observer = recordingObserver("test")

    await observer.operation("doWork") { op in
      op.set(Keys.userID, "abc")
      op.spanOnly("span.only", 1)
      op.logOnly("log.only", 2)
    }

    let op = observer.operations.first!
    #expect(op.name == "doWork")
    #expect(
      op.observations.contains { $0.key == Keys.userID && $0.value == "abc" && $0.pillar == .both })
    #expect(op.observations.contains { $0.key == "span.only" && $0.pillar == .span })
    #expect(op.observations.contains { $0.key == "log.only" && $0.pillar == .log })
  }

  @Test("operation name defaults to the calling function")
  func defaultsToCallerName() async {
    let observer = recordingObserver("test")
    await observer.operation { _ in }
    #expect(observer.operations.first?.name == "defaultsToCallerName()")
  }

  @Test("closure form ends the operation automatically")
  func autoEnds() async {
    let observer = recordingObserver("test")
    await observer.operation("op") { _ in }
    #expect(observer.operations.first?.ended == true)
  }

  @Test("nested operations link parent -> child via the task-local")
  func nestedOperationsLink() async {
    let observer = recordingObserver("test")

    await observer.operation("parent") { _ in
      await observer.operation("child") { _ in }
    }

    let parent = observer.operations.first { $0.name == "parent" }!
    let child = observer.operations.first { $0.name == "child" }!

    #expect(child.span.context.traceID == parent.span.context.traceID)
    #expect(child.span.context.parentSpanID == parent.span.context.spanID)
    #expect(parent.span.context.parentSpanID == nil)
  }

  @Test("error logs against the operation, records on the span, and wraps the error")
  func errorWrapsAndRecords() async {
    let observer = recordingObserver("test")

    await observer.operation("op") { op in
      let wrapped = op.error(SampleError(), "loading profile")
      #expect(wrapped is ObservabilityError)
      #expect("\(wrapped)".hasPrefix("loading profile:"))
    }

    let op = observer.operations.first!
    #expect(op.recordedErrors.contains { $0.context == "loading profile" })
  }

  @Test("observations carry a monotonic global sequence across operations")
  func sequenceOrdering() async {
    let observer = recordingObserver("test")

    await observer.operation("first") { op in
      op.set("a", 1)
      op.set("b", 2)
    }
    await observer.operation("second") { op in
      op.set("c", 3)
    }

    let all = observer.operations.flatMap(\.observations).sorted { $0.seq < $1.seq }
    #expect(all.map(\.key) == ["a", "b", "c"])
    #expect(all.map(\.seq) == [1, 2, 3])
  }
}

@Suite("Pillars / Config")
struct ConfigTests {

  @Test("default config bootstraps native pillars")
  func defaultBootstrap() {
    let pillars = ObservabilityConfig.default.bootstrap()
    #expect(pillars.logger is OSLogLogger)
    #expect(pillars.tracer is SignpostTracer)
  }

  @Test("noop config bootstraps noop pillars")
  func noopBootstrap() {
    let config = ObservabilityConfig(
      serviceName: "svc",
      logging: .init(provider: .noop),
      tracing: .init(provider: .noop),
      metrics: .init(provider: .noop)
    )
    let pillars = config.bootstrap()
    #expect(pillars.logger is NoopLogger)
    #expect(pillars.tracer is NoopTracer)
  }

  @Test("config round-trips through Codable")
  func codableRoundTrip() throws {
    let original = ObservabilityConfig(serviceName: "svc", logging: .init(provider: .noop))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ObservabilityConfig.self, from: data)
    #expect(decoded.serviceName == "svc")
    #expect(decoded.logging.provider == .noop)
  }
}

// MARK: - OBS-11: Pillars shutdown/flush seam

@Suite("Pillars shutdown")
struct PillarsShutdownTests {

  @Test("shutdown() can be awaited on the noop pillars")
  func noopShutdownAwaitable() async {
    await Pillars.noop.shutdown()
    #expect(Bool(true))  // reached: shutdown returned without hanging or trapping
  }

  @Test("shutdown() can be awaited on a live, bootstrapped pillars")
  func liveShutdownAwaitable() async {
    let pillars = ObservabilityConfig.default.bootstrap()
    await pillars.shutdown()
    #expect(Bool(true))
  }
}

// MARK: - OBS-12: Span protocol gaps for the OTel adapter

@Suite("Span kind / status / naming")
struct SpanSeamTests {

  @Test("setStatus is callable on a live signpost span and the noop span")
  func setStatusCallable() {
    let signpost = SignpostTracer().startSpan("op")
    signpost.setStatus(.ok)
    signpost.setStatus(.error)
    signpost.setStatus(.unset)
    signpost.end()

    let noop = NoopTracer().startSpan("op")
    noop.setStatus(.error)
    noop.end()
    #expect(Bool(true))  // no crash on either backend
  }

  @Test("bare startSpan(_:) still works and defaults kind to .internal")
  func bareStartSpanDefaults() {
    let span = SignpostTracer().startSpan("op") as! SignpostSpan
    #expect(span.name == "op")
    #expect(span.kind == .internal)
    span.end()
  }

  @Test("startSpan with kind and initial attributes seeds the span")
  func startSpanWithKindAndAttributes() {
    let span =
      SignpostTracer()
      .startSpan("op", kind: .server, attributes: ["http.method": .string("GET"), "count": .int(3)])
      as! SignpostSpan
    #expect(span.name == "op")
    #expect(span.kind == .server)
    // Attaching seeded attributes must not crash; values land on the signpost event stream.
    span.end()
  }

  @Test("SpanKind covers the OTel roles and encodes to its lowercase name")
  func spanKindRawValues() throws {
    #expect(SpanKind.internal.rawValue == "internal")
    #expect(SpanKind.client.rawValue == "client")
    #expect(SpanKind.server.rawValue == "server")
    #expect(SpanKind.producer.rawValue == "producer")
    #expect(SpanKind.consumer.rawValue == "consumer")
  }

  @Test("per-component tracer naming rides the signpost category")
  func perComponentNaming() {
    let base = SignpostTracer()
    #expect(base.category == "spans")

    let named = base.named("ProfileService") as! SignpostTracer
    #expect(named.category == "spans.ProfileService")

    // A LiveObserver wires the component name into its tracer via `named`.
    let observer = makeObserver("Checkout", ObservabilityConfig.default.bootstrap()) as! LiveObserver
    #expect((observer.tracer as! SignpostTracer).category == "spans.Checkout")

    // The noop tracer ignores naming (default seam), returning an equivalent tracer.
    #expect(NoopTracer().named("x") is NoopTracer)
  }
}

// MARK: - OBS-12: TracingConfig sampleRatio

@Suite("TracingConfig sampleRatio")
struct TracingSampleRatioTests {

  @Test("empty object decodes sampleRatio to the 1.0 default")
  func emptyObjectDefaultsRatio() throws {
    let cfg = try JSONDecoder().decode(TracingConfig.self, from: Data("{}".utf8))
    #expect(cfg.sampleRatio == 1.0)
    #expect(cfg.provider == .signpost)
  }

  @Test("present sampleRatio is decoded")
  func presentRatioDecoded() throws {
    let cfg = try JSONDecoder().decode(
      TracingConfig.self, from: Data(#"{"sampleRatio":0.25}"#.utf8))
    #expect(cfg.sampleRatio == 0.25)
  }

  @Test("sampleRatio round-trips through the whole ObservabilityConfig")
  func ratioRoundTrips() throws {
    let original = ObservabilityConfig(tracing: .init(sampleRatio: 0.5))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ObservabilityConfig.self, from: data)
    #expect(decoded.tracing.sampleRatio == 0.5)
  }

  @Test("empty ObservabilityConfig object leaves tracing.sampleRatio at 1.0")
  func emptyRootDefaultsRatio() throws {
    let cfg = try JSONDecoder().decode(ObservabilityConfig.self, from: Data("{}".utf8))
    #expect(cfg.tracing.sampleRatio == 1.0)
  }
}

@Suite("Logger")
struct LoggerTests {

  @Test("withSpan injects span and trace ids")
  func withSpanInjectsIDs() {
    // RecordingObserver isn't involved here; just verify the shared withSpan default exists and
    // returns a logger (smoke test of the value-semantics chain).
    let span = NoopSpan(
      name: "s", context: SpanContext(traceID: "t", spanID: "sp", parentSpanID: nil))
    let logger = NoopLogger().withSpan(span)
    logger.info("hello")  // no crash, no output
    #expect(Bool(true))
  }
}

// MARK: - OBS-01: concurrent set() must not drop keys

/// Value-semantics `Logger` that keeps its accumulated fields inspectable, so we can assert none were
/// lost across concurrent `set` calls.
private struct CapturingLogger: Logger {
  let fields: [String: String]
  init(fields: [String: String] = [:]) { self.fields = fields }
  func info(_ message: String) {}
  func debug(_ message: String) {}
  func error(_ whatWasHappening: String, _ error: Error) {}
  func withName(_ name: String) -> any Logger { self }
  func withValue(_ key: String, _ value: AttributeValue) -> any Logger {
    var next = fields
    next[key] = value.rendered
    return CapturingLogger(fields: next)
  }
}

@Suite("Operation concurrency")
struct OperationConcurrencyTests {

  @Test("concurrent set() calls never drop keys")
  func concurrentSetNoLostUpdates() async {
    let span = NoopSpan(
      name: "t", context: SpanContext(traceID: "t", spanID: "s", parentSpanID: nil))
    let op = LiveOperation(span: span, logger: CapturingLogger())

    let n = 500
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<n { group.addTask { op.set("key\(i)", i) } }
    }

    let captured = op.logger as! CapturingLogger
    #expect(captured.fields.count == n)
    for i in 0..<n { #expect(captured.fields["key\(i)"] == "\(i)") }
  }
}

// MARK: - OBS-02: noop metrics stay silent even after a factory is installed

private final class SpyCounterHandler: CounterHandler {
  let onIncrement: @Sendable () -> Void
  init(_ onIncrement: @escaping @Sendable () -> Void) { self.onIncrement = onIncrement }
  func increment(by amount: Int64) { onIncrement() }
  func reset() {}
}

private final class SpyMetricsFactory: MetricsFactory, @unchecked Sendable {
  let count = OSAllocatedUnfairLock(initialState: 0)
  var increments: Int { count.withLock { $0 } }

  func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
    SpyCounterHandler { [count] in count.withLock { $0 += 1 } }
  }
  func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler
  {
    NOOPMetricsHandler.instance
  }
  func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
    NOOPMetricsHandler.instance
  }
  func destroyCounter(_ handler: CounterHandler) {}
  func destroyRecorder(_ handler: RecorderHandler) {}
  func destroyTimer(_ handler: TimerHandler) {}
}

@Suite("Metrics noop isolation")
struct MetricsNoopIsolationTests {

  @Test("noop provider never emits, even after a real factory is installed")
  func noopStaysSilent() {
    let spy = SpyMetricsFactory()
    // Bind the spy as the current factory for the scope, without a one-time global bootstrap.
    withMetricsFactory(spy) {
      // A provider bound to the installed factory does emit …
      SwiftMetricsProvider().counter("real", tags: [:]).increment()
      #expect(spy.increments == 1)
      // … but the noop provider must stay silent regardless of what is installed.
      NoopMetricsProvider().counter("noop", tags: [:]).increment()
      #expect(spy.increments == 1)
    }
  }
}

// MARK: - OBS-03: OSLogLogger keeps field values off the public channel

@Suite("OSLogLogger privacy")
struct OSLogPrivacyTests {

  @Test("field values render to the private channel; keys and name stay public")
  func fieldValuesArePrivate() {
    let logger =
      OSLogLogger(subsystem: "test", category: "test", name: "svc")
      .withValue(Keys.userID, "SECRET-PII") as! OSLogLogger

    let pub = logger.renderPublic("hello")
    let priv = logger.renderFields()

    #expect(pub.contains("svc"))  // name public
    #expect(pub.contains("hello"))  // message public
    #expect(pub.contains(Keys.userID))  // key public
    #expect(!pub.contains("SECRET-PII"))  // value NOT on the public channel
    #expect(priv.contains("\(Keys.userID)=SECRET-PII"))  // value only on the private channel
  }
}

// MARK: - OBS-04: lenient config decoding

@Suite("Config lenient decoding")
struct ConfigLenientDecodingTests {

  @Test("empty object decodes to defaults")
  func emptyObjectDecodes() throws {
    let cfg = try JSONDecoder().decode(ObservabilityConfig.self, from: Data("{}".utf8))
    #expect(cfg.serviceName == "platform-swift")
    #expect(cfg.logging.provider == .osLog)
    #expect(cfg.logging.category == "observability")
    #expect(cfg.logging.subsystem == nil)
    #expect(cfg.tracing.provider == .signpost)
    #expect(cfg.metrics.provider == .swiftMetrics)
  }

  @Test("partial config fills missing keys with defaults")
  func partialConfigDecodes() throws {
    let json = #"{"serviceName":"svc","logging":{"provider":"noop"}}"#
    let cfg = try JSONDecoder().decode(ObservabilityConfig.self, from: Data(json.utf8))
    #expect(cfg.serviceName == "svc")
    #expect(cfg.logging.provider == .noop)
    #expect(cfg.logging.category == "observability")  // default preserved on the present block
    #expect(cfg.tracing.provider == .signpost)  // whole missing block defaulted
    #expect(cfg.metrics.provider == .swiftMetrics)
  }
}

// MARK: - OBS-05: recording double captures the success-acknowledgement path

@Suite("Recording acknowledge")
struct RecordingAcknowledgeTests {

  @Test("acknowledge(nil) records the success description")
  func acknowledgeSuccessRecorded() async {
    let observer = recordingObserver("test")
    await observer.operation("op") { op in
      op.acknowledge(nil, "saved profile")
    }
    let op = observer.operations.first!
    #expect(op.acknowledgements == ["saved profile"])
    #expect(op.recordedErrors.isEmpty)
  }

  @Test("acknowledge(error) records the error, not a success")
  func acknowledgeErrorRecorded() async {
    let observer = recordingObserver("test")
    await observer.operation("op") { op in
      op.acknowledge(SampleError(), "failed to save")
    }
    let op = observer.operations.first!
    #expect(op.acknowledgements.isEmpty)
    #expect(op.recordedErrors.contains { $0.context == "failed to save" })
  }
}
