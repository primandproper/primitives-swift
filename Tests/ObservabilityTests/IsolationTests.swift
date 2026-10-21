// Imports Foundation and Observation alongside Observability on purpose: this file compiling is the
// regression test for `Operation` (ambiguous with Foundation's) and `Observation` (shadowing Apple's
// module, which breaks `@Observable`).
import Foundation
import Observation
import Testing

@testable import Observability

/// Mutates its own state from inside nested `operation` bodies with no `await` on the mutation, which
/// only compiles if the bodies run on the actor.
private actor ActorRunner {
  let observer: any Observer
  private(set) var count = 0

  init(observer: any Observer) { self.observer = observer }

  func run() async {
    await observer.operation("parent") { _ in
      count += 1
      await observer.operation(name: "child") { op in
        count += 1
        op.set("count", count)
      }
    }
  }
}

@MainActor
private final class MainActorRunner {
  let observer: any Observer
  private(set) var count = 0

  init(observer: any Observer) { self.observer = observer }

  func run() async {
    await observer.operation("parent") { _ in
      count += 1
      await observer.operation(name: "child") { op in
        count += 1
        op.set("count", count)
      }
    }
  }
}

@available(macOS 14, iOS 17, *)
@Observable
private final class ObservableModel {
  var label = ""
  @ObservationIgnored let observer: any Observer

  init(observer: any Observer) { self.observer = observer }

  func load() async {
    await observer.operation("load") { op in
      label = describe(op)
    }
  }

  private func describe(_ op: any ObservedOperation) -> String {
    op.span.name
  }
}

private func expectLinked(_ observer: RecordingObserver) {
  let parent = observer.operations.first { $0.name == "parent" }!
  let child = observer.operations.first { $0.name == "child" }!
  #expect(child.span.context.traceID == parent.span.context.traceID)
  #expect(child.span.context.parentSpanID == parent.span.context.spanID)
  #expect(child.value(forKey: "count") == "2")
  #expect(parent.ended && child.ended)
}

private func expectLinked(_ tracer: MockTracer) {
  let parent = tracer.span(named: "parent")!
  let child = tracer.span(named: "child")!
  #expect(child.context.traceID == parent.context.traceID)
  #expect(child.context.parentSpanID == parent.context.spanID)
}

@Suite("Observer isolation")
struct ObserverIsolationTests {

  @Test("operation bodies run on the calling actor; nested operations still link")
  func fromActor() async {
    let observer = recordingObserver("test")
    let runner = ActorRunner(observer: observer)

    await runner.run()

    #expect(await runner.count == 2)
    expectLinked(observer)
  }

  @Test("operation bodies run on the main actor; nested operations still link")
  @MainActor
  func fromMainActor() async {
    let observer = recordingObserver("test")
    let runner = MainActorRunner(observer: observer)

    await runner.run()

    #expect(runner.count == 2)
    expectLinked(observer)
  }

  @Test("live observer: nested operations from an actor link parent -> child")
  func liveFromActor() async {
    let tracer = MockTracer()
    let observer = LiveObserver(name: "svc", logger: MockLogger(sink: LogSink()), tracer: tracer)
    let runner = ActorRunner(observer: observer)

    await runner.run()

    #expect(await runner.count == 2)
    expectLinked(tracer)
  }

  @Test("live observer: nested operations from the main actor link parent -> child")
  @MainActor
  func liveFromMainActor() async {
    let tracer = MockTracer()
    let observer = LiveObserver(name: "svc", logger: MockLogger(sink: LogSink()), tracer: tracer)
    let runner = MainActorRunner(observer: observer)

    await runner.run()

    #expect(runner.count == 2)
    expectLinked(tracer)
  }

  @Test("an @Observable model can log through Observability with no selective imports")
  @available(macOS 14, iOS 17, *)
  @MainActor
  func observableModel() async {
    let model = ObservableModel(observer: recordingObserver("test"))

    await model.load()

    #expect(model.label == "load")
  }
}
