import Testing

@testable import CircuitBreaking

private struct Boom: Error {}

@Suite("MockCircuitBreaker")
struct MockCircuitBreakerTests {
  @Test("records failure and success calls")
  func recordsOutcomes() async {
    let breaker = MockCircuitBreaker()
    await breaker.recordFailure()
    await breaker.recordFailure()
    await breaker.recordSuccess()

    #expect(await breaker.recordFailureCallCount == 2)
    #expect(await breaker.recordSuccessCallCount == 1)
  }

  @Test("answers the gate from the injected flag, and setCanProceed flips it")
  func gate() async {
    let breaker = MockCircuitBreaker(canProceed: true)
    #expect(await breaker.canProceed())
    #expect(await breaker.cannotProceed() == false)

    await breaker.setCanProceed(false)
    #expect(await breaker.canProceed() == false)
    #expect(await breaker.cannotProceed())
    // canProceed was queried four times above (twice directly, twice via cannotProceed).
    #expect(await breaker.canProceedCallCount == 4)
  }

  @Test("the default execute helper records success and failure through the mock")
  func executeRecords() async {
    let breaker = MockCircuitBreaker()
    _ = try? await breaker.execute { 1 }
    await #expect(throws: Boom.self) { try await breaker.execute { throw Boom() } }

    #expect(await breaker.recordSuccessCallCount == 1)
    #expect(await breaker.recordFailureCallCount == 1)
  }
}

@Suite("MockKeyedCircuitBreaker")
struct MockKeyedCircuitBreakerTests {
  @Test("records requested keys and returns the injected breaker")
  func recordsKeys() {
    let inner = NoopCircuitBreaker()
    let keyed = MockKeyedCircuitBreaker(breaker: inner)

    _ = keyed.breaker(for: "tenant-1")
    _ = keyed.breaker(for: "tenant-2")

    #expect(keyed.requestedKeys == ["tenant-1", "tenant-2"])
  }

  @Test("defaults to a NoopCircuitBreaker")
  func defaultsToNoop() {
    let keyed = MockKeyedCircuitBreaker()
    #expect(keyed.breaker(for: "any") is NoopCircuitBreaker)
  }
}
