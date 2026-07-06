import Observability
import Testing

@testable import HealthCheck

@Suite("HealthCheckRegistry")
struct HealthCheckRegistryTests {
  @Test("an empty registry reports up with no components")
  func emptyRegistryReportsUp() async {
    let registry = HealthCheckRegistry(observer: recordingObserver("test"))
    let result = await registry.checkAll()
    #expect(result.status == .up)
    #expect(result.components.isEmpty)
  }

  @Test("all healthy checkers aggregate to up")
  func allHealthyAggregatesUp() async {
    let registry = HealthCheckRegistry(observer: recordingObserver("test"))
    await registry.register(NoopChecker(name: "a"))
    await registry.register(NoopChecker(name: "b"))

    let result = await registry.checkAll()

    #expect(result.status == .up)
    #expect(result.components.count == 2)
    #expect(result.components["a"] == ComponentResult(status: .up))
    #expect(result.components["b"] == ComponentResult(status: .up))
  }

  @Test("one unhealthy checker flips the aggregate status to down")
  func oneUnhealthyFlipsAggregateDown() async {
    let registry = HealthCheckRegistry(observer: recordingObserver("test"))
    await registry.register(NoopChecker(name: "up"))
    let down = CheckerMock(name: "down") { throw HealthCheckError.unreachable("unsatisfied") }
    await registry.register(down)

    let result = await registry.checkAll()

    #expect(result.status == .down)
    #expect(result.components.count == 2)
    #expect(result.components["up"] == ComponentResult(status: .up))
    #expect(result.components["down"]?.status == .down)
    #expect(result.components["down"]?.message != nil)
  }

  @Test("a check that outlives its timeout is classified down, not left hanging")
  func perCheckTimeoutFires() async {
    let registry = HealthCheckRegistry(
      checkTimeout: .milliseconds(20), observer: recordingObserver("test"))
    let slow = CheckerMock(name: "slow") {
      try await Task.sleep(for: .seconds(30))
    }
    await registry.register(slow)

    let clock = ContinuousClock()
    let start = clock.now
    let result = await registry.checkAll()
    let elapsed = start.duration(to: clock.now)

    // The registry must not wait anywhere near the checker's 30s sleep for the result to come back.
    #expect(elapsed < .seconds(5))
    #expect(result.status == .down)
    #expect(result.components["slow"]?.status == .down)
    if case .some(let message) = result.components["slow"]?.message {
      #expect(message.contains("slow"))
    } else {
      Issue.record("expected a timeout message on the \"slow\" component")
    }
  }

  @Test("registered checks run concurrently, not serially")
  func checksRunConcurrently() async {
    let registry = HealthCheckRegistry(observer: recordingObserver("test"))
    let perCheckDelay: Duration = .milliseconds(150)
    for index in 0..<5 {
      let checker = CheckerMock(name: "checker-\(index)") {
        try await Task.sleep(for: perCheckDelay)
      }
      await registry.register(checker)
    }

    let clock = ContinuousClock()
    let start = clock.now
    let result = await registry.checkAll()
    let elapsed = start.duration(to: clock.now)

    #expect(result.status == .up)
    #expect(result.components.count == 5)
    // Serial execution would take >= 5 * 150ms = 750ms; concurrent execution should land well under that.
    #expect(elapsed < .milliseconds(500))
  }

  @Test("register accumulates checkers across multiple calls")
  func registerAccumulates() async {
    let registry = HealthCheckRegistry(observer: recordingObserver("test"))
    await registry.register(NoopChecker(name: "a"))
    await registry.register(NoopChecker(name: "a"))

    let result = await registry.checkAll()

    // Two checkers registered under the same name: the last one written to the components dictionary
    // wins, matching the plain `map[string]ComponentResult` assignment in Go's aggregation loop — there's
    // no dedup by name on either side.
    #expect(result.components.count == 1)
  }
}
