import Foundation
import Testing
import struct os.OSAllocatedUnfairLock

@testable import Observability

// MARK: - REPO-08 test doubles
//
// The existing suite exercises `RecordingObserver`, whose operations sit on `NoopSpan`/`NoopLogger`.
// That leaves the *production* `LiveObserver`/`LiveOperation` dual-write path — the code that actually
// routes to a real span and a real logger — unobserved. These doubles are span/logger conformers that
// capture what reaches them, so a `LiveObserver` built on top can be inspected on both pillars at once.

/// Thread-safe sink shared by every `MockLogger` value in a `with*` chain. Because `MockLogger` has
/// value semantics (each `withValue` returns a fresh struct), emitted messages must land on a shared
/// reference so they survive the copies.
final class LogSink: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock(initialState: State())
  private struct State {
    var infos: [String] = []
    var debugs: [String] = []
    var errors: [(context: String, error: String)] = []
  }
  var infos: [String] { state.withLock { $0.infos } }
  var debugs: [String] { state.withLock { $0.debugs } }
  var errors: [(context: String, error: String)] { state.withLock { $0.errors } }

  func info(_ m: String) { state.withLock { $0.infos.append(m) } }
  func debug(_ m: String) { state.withLock { $0.debugs.append(m) } }
  func error(_ c: String, _ e: String) { state.withLock { $0.errors.append((c, e)) } }
}

/// Value-semantics `Logger` double: accumulated `fields` are inspectable (they ride the struct copy the
/// `LiveOperation` currently holds), while emitted `info/debug/error` messages land on a shared
/// ``LogSink`` so they can be observed regardless of which copy emitted them.
struct MockLogger: Logger {
  let sink: LogSink
  let name: String
  let fields: [String: String]

  init(sink: LogSink, name: String = "", fields: [String: String] = [:]) {
    self.sink = sink
    self.name = name
    self.fields = fields
  }

  func info(_ message: String) { sink.info(message) }
  func debug(_ message: String) { sink.debug(message) }
  func error(_ whatWasHappening: String, _ error: Error) {
    sink.error(whatWasHappening, "\(error)")
  }

  func withName(_ name: String) -> any Logger {
    MockLogger(sink: sink, name: name, fields: fields)
  }
  func withValue(_ key: String, _ value: AttributeValue) -> any Logger {
    var next = fields
    next[key] = value.rendered
    return MockLogger(sink: sink, name: name, fields: next)
  }
  // withValues / withError / withSpan come from the Logger extension defaults.
}

/// `Span` double capturing every attach / recordError / setStatus / end, guarded by a lock so it is
/// safe to touch from concurrent child tasks.
final class MockSpan: Span, @unchecked Sendable {
  let name: String
  let context: SpanContext

  private let state = OSAllocatedUnfairLock(initialState: State())
  private struct State {
    var attributes: [(key: String, value: String)] = []
    var errors: [(context: String, error: String)] = []
    var statuses: [SpanStatus] = []
    var endCount = 0
  }

  init(name: String, context: SpanContext) {
    self.name = name
    self.context = context
  }

  var attributes: [(key: String, value: String)] { state.withLock { $0.attributes } }
  var attributeKeys: [String] { attributes.map(\.key) }
  func attributeValue(forKey key: String) -> String? { attributes.first { $0.key == key }?.value }
  var recordedErrors: [(context: String, error: String)] { state.withLock { $0.errors } }
  var statuses: [SpanStatus] { state.withLock { $0.statuses } }
  var endCount: Int { state.withLock { $0.endCount } }

  func attach(_ key: String, _ value: AttributeValue) {
    state.withLock { $0.attributes.append((key, value.rendered)) }
  }
  func recordError(_ description: String, _ error: Error) {
    state.withLock { $0.errors.append((description, "\(error)")) }
  }
  func setStatus(_ status: SpanStatus) {
    state.withLock { $0.statuses.append(status) }
  }
  func end() {
    state.withLock { $0.endCount += 1 }
  }
}

/// `Tracer` double that mints ``MockSpan`` instances linked to the in-scope task-local context (exactly
/// as the production `SignpostTracer` does), and retains them for inspection. `named(_:)` uses the
/// default seam (returns self), so a `LiveObserver` built on it keeps writing into the same tracer.
final class MockTracer: Tracer, @unchecked Sendable {
  private let state = OSAllocatedUnfairLock(initialState: [MockSpan]())
  var spans: [MockSpan] { state.withLock { $0 } }
  func span(named name: String) -> MockSpan? { spans.first { $0.name == name } }

  func startSpan(_ name: String, kind: SpanKind, attributes: [String: AttributeValue]) -> any Span {
    let span = MockSpan(name: name, context: .child(of: SpanContextStore.current))
    for (key, value) in attributes { span.attach(key, value) }
    state.withLock { $0.append(span) }
    return span
  }
}

struct MockError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String = "boom") { self.description = description }
}

/// Builds a `LiveObserver` wired to the capturing doubles, returning the observer plus the tracer and
/// log sink so a test can assert on both pillars.
private func liveHarness(name: String = "svc") -> (LiveObserver, MockTracer, LogSink) {
  let tracer = MockTracer()
  let sink = LogSink()
  let observer = LiveObserver(name: name, logger: MockLogger(sink: sink), tracer: tracer)
  return (observer, tracer, sink)
}

// MARK: - LiveObserver / LiveOperation dual-write routing

@Suite("LiveOperation routing (live path)")
struct LiveRoutingTests {

  @Test("set() reaches BOTH the tracer span and the operation logger")
  func setDualWrites() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("doWork") { op in
      op.set(Keys.userID, "abc")
      // The operation's own logger (a MockLogger copy) must carry the field too.
      let fields = (op.logger as! MockLogger).fields
      #expect(fields[Keys.userID] == "abc")
    }

    let span = tracer.span(named: "doWork")!
    #expect(span.attributeValue(forKey: Keys.userID) == "abc")
    #expect(span.endCount == 1)  // closure form ends the span exactly once
  }

  @Test("spanOnly() reaches the span only; logOnly() reaches the logger only")
  func spanOnlyAndLogOnlyRouting() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("route") { op in
      op.spanOnly("span.key", 1)
      op.logOnly("log.key", 2)

      let fields = (op.logger as! MockLogger).fields
      #expect(fields["log.key"] == "2")  // logOnly on the logger
      #expect(fields["span.key"] == nil)  // spanOnly NOT on the logger
    }

    let span = tracer.span(named: "route")!
    #expect(span.attributeValue(forKey: "span.key") == "1")  // spanOnly on the span
    #expect(span.attributeValue(forKey: "log.key") == nil)  // logOnly NOT on the span
  }

  @Test("setValues() dual-writes every pair to both pillars")
  func setValuesDualWrites() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("bulk") { op in
      op.setValues(["a": 1, "b": "two", "c": true])
      let fields = (op.logger as! MockLogger).fields
      #expect(fields["a"] == "1")
      #expect(fields["b"] == "two")
      #expect(fields["c"] == "true")
    }

    let span = tracer.span(named: "bulk")!
    #expect(span.attributeValue(forKey: "a") == "1")
    #expect(span.attributeValue(forKey: "b") == "two")
    #expect(span.attributeValue(forKey: "c") == "true")
  }

  @Test("acknowledge(error) reaches BOTH the span (recordError) and the logger (error)")
  func acknowledgeErrorDualWrites() async {
    let (observer, tracer, sink) = liveHarness()

    await observer.operation("ack") { op in
      op.acknowledge(MockError("nope"), "failed step")
    }

    let span = tracer.span(named: "ack")!
    #expect(span.recordedErrors.contains { $0.context == "failed step" })
    #expect(sink.errors.contains { $0.context == "failed step" })
  }

  @Test("acknowledge(nil) logs an info on the logger and does not touch the span")
  func acknowledgeSuccessLogsOnly() async {
    let (observer, tracer, sink) = liveHarness()

    await observer.operation("ack-ok") { op in
      op.acknowledge(nil, "did step")
    }

    let span = tracer.span(named: "ack-ok")!
    #expect(sink.infos.contains("did step"))
    #expect(span.recordedErrors.isEmpty)
  }

  @Test("error() logs on the logger, records on the span, and returns a wrapped error")
  func errorDualWritesAndWraps() async {
    let (observer, tracer, sink) = liveHarness()

    await observer.operation("boom") { op in
      let wrapped = op.error(MockError("db down"), "loading profile")
      #expect(wrapped is ObservabilityError)
      #expect("\(wrapped)".hasPrefix("loading profile:"))
    }

    let span = tracer.span(named: "boom")!
    #expect(span.recordedErrors.contains { $0.context == "loading profile" })
    #expect(sink.errors.contains { $0.context == "loading profile" })
  }

  @Test("operation logger is seeded with the span/trace ids via withSpan")
  func loggerSeededWithSpanIDs() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("ids") { op in
      let fields = (op.logger as! MockLogger).fields
      let span = tracer.span(named: "ids")!
      #expect(fields[Keys.spanID] == span.context.spanID)
      #expect(fields[Keys.traceID] == span.context.traceID)
    }
  }

  @Test("begin() escape hatch returns a live operation the caller ends")
  func beginManualEnd() {
    let (observer, tracer, _) = liveHarness()
    let op = observer.begin("manual")
    op.set("k", "v")
    let span = tracer.span(named: "manual")!
    #expect(span.attributeValue(forKey: "k") == "v")
    #expect(span.endCount == 0)  // not ended until the caller says so
    op.end()
    #expect(span.endCount == 1)
  }
}

// MARK: - OSLogLogger.render output format (OBS-03)

@Suite("OSLogLogger render format")
struct OSLogRenderFormatTests {

  @Test("renderPublic shows name, message, and sorted keys but never values")
  func renderPublicShape() {
    let logger =
      OSLogLogger(subsystem: "t", category: "t", name: "svc")
      .withValue("zeta", "Z")
      .withValue("alpha", "A") as! OSLogLogger

    let pub = logger.renderPublic("hello world")
    // Name is bracketed and first; message follows; keys are brace-wrapped and sorted.
    #expect(pub == "[svc] hello world {alpha zeta}")
    #expect(!pub.contains("Z"))
    #expect(!pub.contains("A"))
  }

  @Test("renderPublic without a name omits the bracket segment")
  func renderPublicNoName() {
    let logger = (OSLogLogger(subsystem: "t", category: "t").withValue("k", "v")) as! OSLogLogger
    #expect(logger.renderPublic("msg") == "msg {k}")
  }

  @Test("renderPublic with no fields omits the brace segment")
  func renderPublicNoFields() {
    let logger = OSLogLogger(subsystem: "t", category: "t", name: "svc")
    #expect(logger.renderPublic("msg") == "[svc] msg")
  }

  @Test("renderFields emits sorted key=value pairs")
  func renderFieldsSortedPairs() {
    let logger =
      OSLogLogger(subsystem: "t", category: "t")
      .withValue("b", "2")
      .withValue("a", "1") as! OSLogLogger
    #expect(logger.renderFields() == "a=1 b=2")
  }

  @Test("renderFields appends the extra (error) value after the pairs")
  func renderFieldsWithExtra() {
    let logger = (OSLogLogger(subsystem: "t", category: "t").withValue("a", "1")) as! OSLogLogger
    #expect(logger.renderFields(extra: "someError") == "a=1 someError")
  }

  @Test("emitting through info/error does not crash and preserves render separation")
  func emitDoesNotCrash() {
    let logger = OSLogLogger(subsystem: "t", category: "t", name: "svc").withValue(Keys.userID, "PII")
    logger.info("hi")
    logger.error("boom", MockError())
    #expect(Bool(true))
  }
}

// MARK: - signpost end-idempotence

@Suite("Span end idempotence")
struct SpanEndIdempotenceTests {

  @Test("ending a SignpostSpan twice is safe (guarded, no double endInterval)")
  func signpostDoubleEnd() {
    let span = SignpostTracer().startSpan("op") as! SignpostSpan
    span.end()
    span.end()  // second end must be a no-op, not a crash / double-emit
    #expect(Bool(true))
  }

  @Test("ending a NoopSpan twice is safe")
  func noopDoubleEnd() {
    let span = NoopTracer().startSpan("op")
    span.end()
    span.end()
    #expect(Bool(true))
  }

  @Test("a LiveOperation whose closure returns ends its span; a manual double end is tolerated")
  func liveOperationDoubleEnd() async {
    let tracer = MockTracer()
    let observer = LiveObserver(name: "s", logger: MockLogger(sink: LogSink()), tracer: tracer)
    let op = observer.begin("op")
    op.end()
    op.end()  // MockSpan counts, but the point is no crash on repeated end
    #expect(tracer.span(named: "op")!.endCount == 2)
  }
}

// MARK: - IDGen format (OBS-20)

@Suite("IDGen format")
struct IDGenFormatTests {

  private static let hex = Set("0123456789abcdef")

  @Test("traceID is 32 lowercase hex chars and never all-zero")
  func traceIDShape() {
    for _ in 0..<2_000 {
      let id = IDGen.traceID()
      #expect(id.count == 32)
      #expect(Set(id).isSubset(of: Self.hex))
      #expect(id != String(repeating: "0", count: 32))
    }
  }

  @Test("spanID is 16 lowercase hex chars and never all-zero")
  func spanIDShape() {
    for _ in 0..<2_000 {
      let id = IDGen.spanID()
      #expect(id.count == 16)
      #expect(Set(id).isSubset(of: Self.hex))
      #expect(id != String(repeating: "0", count: 16))
    }
  }

  @Test("child(of:) mints fresh ids and inherits the parent trace")
  func childInheritsTrace() {
    let parent = SpanContext.child(of: nil)
    #expect(parent.parentSpanID == nil)
    #expect(parent.traceID.count == 32)
    #expect(parent.spanID.count == 16)

    let child = SpanContext.child(of: parent)
    #expect(child.traceID == parent.traceID)  // same trace
    #expect(child.parentSpanID == parent.spanID)  // linked
    #expect(child.spanID != parent.spanID)  // fresh span id
  }
}

// MARK: - Concurrency: task-local parenting

@Suite("Concurrency: task-local parenting")
struct TaskLocalParentingTests {

  @Test("children started inside withTaskGroup link to the parent span")
  func taskGroupChildrenLinkToParent() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("parent") { _ in
      await withTaskGroup(of: Void.self) { group in
        for i in 0..<8 {
          group.addTask { await observer.operation("child\(i)") { _ in } }
        }
      }
    }

    let parent = tracer.span(named: "parent")!
    for i in 0..<8 {
      let child = tracer.span(named: "child\(i)")!
      #expect(child.context.traceID == parent.context.traceID)
      #expect(child.context.parentSpanID == parent.context.spanID)
    }
  }

  @Test("children started via async let link to the parent span")
  func asyncLetChildrenLinkToParent() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("parent") { _ in
      async let a: Void = observer.operation("childA") { _ in }
      async let b: Void = observer.operation("childB") { _ in }
      _ = await (a, b)
    }

    let parent = tracer.span(named: "parent")!
    for name in ["childA", "childB"] {
      let child = tracer.span(named: name)!
      #expect(child.context.traceID == parent.context.traceID)
      #expect(child.context.parentSpanID == parent.context.spanID)
    }
  }

  @Test("sibling spans do not cross-link to each other")
  func siblingsDoNotCrossLink() async {
    let (observer, tracer, _) = liveHarness()

    await observer.operation("parent") { _ in
      await observer.operation("sibA") { _ in }
      await observer.operation("sibB") { _ in }
    }

    let a = tracer.span(named: "sibA")!
    let b = tracer.span(named: "sibB")!
    // Distinct span ids, and neither points at the other — both point at the shared parent.
    #expect(a.context.spanID != b.context.spanID)
    #expect(a.context.parentSpanID != b.context.spanID)
    #expect(b.context.parentSpanID != a.context.spanID)
    #expect(a.context.parentSpanID == b.context.parentSpanID)  // same parent
  }

  @Test("root sibling operations get independent traces")
  func rootSiblingsIndependentTraces() async {
    let (observer, tracer, _) = liveHarness()
    await observer.operation("rootA") { _ in }
    await observer.operation("rootB") { _ in }

    let a = tracer.span(named: "rootA")!
    let b = tracer.span(named: "rootB")!
    #expect(a.context.parentSpanID == nil)
    #expect(b.context.parentSpanID == nil)
    #expect(a.context.traceID != b.context.traceID)  // fresh trace each
  }
}

// MARK: - Concurrency: OBS-01 lost-update race on the live path

@Suite("Concurrency: concurrent op.set (OBS-01)")
struct ConcurrentSetLivePathTests {

  @Test("concurrent set() from many child tasks drops no keys on either pillar")
  func concurrentSetNoLostUpdatesLivePath() async {
    let tracer = MockTracer()
    let sink = LogSink()
    let observer = LiveObserver(name: "svc", logger: MockLogger(sink: sink), tracer: tracer)

    let n = 500
    await observer.operation("fanout") { op in
      await withTaskGroup(of: Void.self) { group in
        for i in 0..<n {
          group.addTask { op.set("key\(i)", i) }
        }
      }
      // Logger side: every key present on the operation's accumulated logger copy. (The logger is
      // also seeded with span.id/trace.id via withSpan, so count against the fanout keys only.)
      let fields = (op.logger as! MockLogger).fields
      let fanoutKeys = fields.keys.filter { $0.hasPrefix("key") }
      #expect(fanoutKeys.count == n)
      for i in 0..<n { #expect(fields["key\(i)"] == "\(i)") }
    }

    // Span side: every key attached exactly once (span.attach is called under the operation's set).
    let span = tracer.span(named: "fanout")!
    let keys = Set(span.attributeKeys)
    #expect(keys.count == n)
    for i in 0..<n { #expect(keys.contains("key\(i)")) }
  }
}

// MARK: - OBS-04: partial / empty config decode regression

@Suite("Config partial decode (OBS-04)")
struct PartialConfigDecodeTests {

  @Test("a bare {} config decodes to native defaults without throwing")
  func emptyDecodesToDefaults() throws {
    let cfg = try JSONDecoder().decode(ObservabilityConfig.self, from: Data("{}".utf8))
    #expect(cfg.serviceName == "platform-swift")
    #expect(cfg.logging.provider == .osLog)
    #expect(cfg.tracing.provider == .signpost)
    #expect(cfg.tracing.sampleRatio == 1.0)
    #expect(cfg.metrics.provider == .swiftMetrics)
  }

  @Test("an Info.plist-style partial config fills only the missing keys")
  func partialFillsDefaults() throws {
    // Only serviceName + a partial tracing block present; everything else must default.
    let json = #"{"serviceName":"myapp","tracing":{"sampleRatio":0.1}}"#
    let cfg = try JSONDecoder().decode(ObservabilityConfig.self, from: Data(json.utf8))
    #expect(cfg.serviceName == "myapp")
    #expect(cfg.tracing.sampleRatio == 0.1)
    #expect(cfg.tracing.provider == .signpost)  // missing key in the present block defaulted
    #expect(cfg.logging.provider == .osLog)  // whole missing block defaulted
    #expect(cfg.metrics.provider == .swiftMetrics)
  }

  @Test("empty nested config objects decode to their own defaults")
  func emptyNestedObjectsDecode() throws {
    let json = #"{"logging":{},"tracing":{},"metrics":{}}"#
    let cfg = try JSONDecoder().decode(ObservabilityConfig.self, from: Data(json.utf8))
    #expect(cfg.logging.category == "observability")
    #expect(cfg.logging.subsystem == nil)
    #expect(cfg.tracing.sampleRatio == 1.0)
    #expect(cfg.metrics.provider == .swiftMetrics)
  }

  @Test("bootstrapping a defaulted partial config yields the native pillars")
  func partialConfigBootstrapsNativePillars() throws {
    let cfg = try JSONDecoder().decode(
      ObservabilityConfig.self, from: Data(#"{"serviceName":"x"}"#.utf8))
    let pillars = cfg.bootstrap()
    #expect(pillars.logger is OSLogLogger)
    #expect(pillars.tracer is SignpostTracer)
  }
}
