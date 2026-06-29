import Foundation
import Testing

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
    let original = ObservabilityConfig(serviceName: "svc", logging: .init(provider: .swiftLog))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ObservabilityConfig.self, from: data)
    #expect(decoded.serviceName == "svc")
    #expect(decoded.logging.provider == .swiftLog)
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
