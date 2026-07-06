import Testing

@testable import CircuitBreaking

@Suite("PartitionedCircuitBreaker")
struct PartitionedCircuitBreakerTests {
  @Test("routes a registered key to its dedicated breaker and others to the global one")
  func routesByKey() {
    let dedicated = StandardCircuitBreaker(
      name: "dedicated", errorRatePercentage: 50, minimumSampleThreshold: 1)
    let global = StandardCircuitBreaker(
      name: "global", errorRatePercentage: 50, minimumSampleThreshold: 1)

    let keyed = PartitionedCircuitBreaker(global: global, breakers: ["123": dedicated])

    // Actors are reference types, so identity distinguishes the dedicated breaker from the shared one.
    #expect(keyed.breaker(for: "123") as? StandardCircuitBreaker<ContinuousClock> === dedicated)
    #expect(keyed.breaker(for: "456") as? StandardCircuitBreaker<ContinuousClock> === global)
    #expect(keyed.breaker(for: "789") as? StandardCircuitBreaker<ContinuousClock> === global)
  }

  @Test("with no registered breakers every key falls back to the global one")
  func fallsBackToGlobal() {
    let global = NoopCircuitBreaker()
    let keyed = PartitionedCircuitBreaker(global: global)

    #expect(keyed.breaker(for: "anything") is NoopCircuitBreaker)
  }

  /// The core behavior: one broken key is blocked while other keys, served by the healthy global
  /// breaker, still proceed.
  @Test("breaks one key in isolation")
  func breaksInIsolation() async {
    let broken = StandardCircuitBreaker(
      name: "broken", errorRatePercentage: 50, minimumSampleThreshold: 1, resetTimeout: .seconds(60)
    )
    await broken.recordFailure()  // trips the heavy tenant's breaker

    let global = StandardCircuitBreaker(
      name: "global", errorRatePercentage: 50, minimumSampleThreshold: 1_000_000)

    let keyed = PartitionedCircuitBreaker(global: global, breakers: ["123": broken])

    #expect(await keyed.breaker(for: "123").cannotProceed())  // heavy tenant is circuit broken
    #expect(await keyed.breaker(for: "456").canProceed())  // small tenant still proceeds
  }
}

@Suite("NoopKeyedCircuitBreaker")
struct NoopKeyedCircuitBreakerTests {
  @Test("always proceeds for any key")
  func alwaysProceeds() async {
    let keyed = NoopKeyedCircuitBreaker()

    // `for` yields an existential `any CircuitBreaker`, whose accessors are `async`.
    let cb = keyed.breaker(for: "123")
    #expect(await cb.canProceed())
    await cb.recordFailure()
    #expect(await cb.canProceed())
    #expect(await !cb.cannotProceed())
  }
}
