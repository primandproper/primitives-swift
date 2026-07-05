import Testing

@testable import CircuitBreaking

/// Race-free call counter for `@Sendable` operation closures, which can't capture a mutable `var` under
/// strict concurrency.
private actor CallCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private struct Boom: Error {}

@Suite("StandardCircuitBreaker state machine")
struct StandardCircuitBreakerTests {
  /// A breaker that is effectively impossible to trip, for happy-path assertions.
  private func healthyBreaker() -> StandardCircuitBreaker {
    StandardCircuitBreaker(
      name: "healthy", errorRatePercentage: 100, minimumSampleThreshold: 1_000_000,
      resetTimeout: .seconds(60))
  }

  @Test("starts closed and lets operations proceed")
  func startsClosed() async {
    let cb = healthyBreaker()
    #expect(await cb.canProceed())
    #expect(await !cb.cannotProceed())
  }

  @Test("execute runs the operation and returns its value while closed")
  func executeHappyPath() async throws {
    let cb = healthyBreaker()
    let ran = CallCounter()

    let result = try await cb.execute {
      await ran.increment()
      return 42
    }

    #expect(result == 42)
    #expect(await ran.count == 1)
  }

  @Test("trips open after the failure threshold and error rate are met")
  func tripsOpen() async {
    // 50% at 2 samples: two failures is 100% over 2 samples -> trips.
    let cb = StandardCircuitBreaker(
      name: "trip", errorRatePercentage: 50, minimumSampleThreshold: 2, resetTimeout: .seconds(60))

    #expect(await cb.canProceed())
    await cb.recordFailure()
    // One failure is below the sample threshold, so it hasn't tripped yet.
    #expect(await cb.canProceed())
    await cb.recordFailure()
    #expect(await cb.cannotProceed())
  }

  @Test("does not trip below the minimum sample threshold")
  func respectsSampleThreshold() async {
    let cb = StandardCircuitBreaker(
      name: "samples", errorRatePercentage: 1, minimumSampleThreshold: 5, resetTimeout: .seconds(60))

    // A 100% error rate, but only 4 samples < threshold of 5.
    for _ in 0..<4 { await cb.recordFailure() }
    #expect(await cb.canProceed())
  }

  @Test("rejects fast with CircuitOpenError while open, without running the operation")
  func rejectsFastWhileOpen() async {
    let cb = StandardCircuitBreaker(
      name: "open", errorRatePercentage: 50, minimumSampleThreshold: 1, resetTimeout: .seconds(60))
    await cb.recordFailure()  // trips immediately (100% over 1 sample)
    #expect(await cb.cannotProceed())

    let ran = CallCounter()
    await #expect(throws: CircuitOpenError.self) {
      try await cb.execute {
        await ran.increment()
        return 0
      }
    }
    #expect(await ran.count == 0)
  }

  @Test("transitions to half-open after the reset timeout elapses")
  func transitionsToHalfOpen() async throws {
    let cb = StandardCircuitBreaker(
      name: "halfopen", errorRatePercentage: 50, minimumSampleThreshold: 1,
      resetTimeout: .milliseconds(50))
    await cb.recordFailure()  // trips
    #expect(await cb.cannotProceed())

    try await Task.sleep(for: .milliseconds(120))
    #expect(await cb.canProceed())  // half-open: a trial is allowed
  }

  @Test("closes again when the half-open trial succeeds")
  func closesOnHalfOpenSuccess() async throws {
    let cb = StandardCircuitBreaker(
      name: "close", errorRatePercentage: 50, minimumSampleThreshold: 2,
      resetTimeout: .milliseconds(50))
    await cb.recordFailure()
    await cb.recordFailure()  // trips
    #expect(await cb.cannotProceed())

    try await Task.sleep(for: .milliseconds(120))
    #expect(await cb.canProceed())  // half-open

    await cb.recordSuccess()  // trial succeeds -> close and clear the window
    #expect(await cb.canProceed())

    // The window was cleared, so a single fresh failure (below the threshold of 2) can't re-trip it.
    await cb.recordFailure()
    #expect(await cb.canProceed())
  }

  @Test("re-opens when the half-open trial fails")
  func reopensOnHalfOpenFailure() async throws {
    let cb = StandardCircuitBreaker(
      name: "reopen", errorRatePercentage: 50, minimumSampleThreshold: 1,
      resetTimeout: .milliseconds(50))
    await cb.recordFailure()  // trips
    try await Task.sleep(for: .milliseconds(120))
    #expect(await cb.canProceed())  // half-open

    await cb.recordFailure()  // trial fails -> back to open
    #expect(await cb.cannotProceed())
  }

  @Test("execute records failures and rethrows, tripping after enough of them")
  func executeRecordsFailures() async {
    let cb = StandardCircuitBreaker(
      name: "exec", errorRatePercentage: 50, minimumSampleThreshold: 2, resetTimeout: .seconds(60))

    for _ in 0..<2 {
      await #expect(throws: Boom.self) {
        try await cb.execute { throw Boom() }
      }
    }

    #expect(await cb.cannotProceed())
  }

  @Test("execute rethrows cancellation without counting it as a failure")
  func executeIgnoresCancellation() async {
    // Rate 1% at 1 sample would trip on any single real failure; cancellation must not be one.
    let cb = StandardCircuitBreaker(
      name: "cancel", errorRatePercentage: 1, minimumSampleThreshold: 1, resetTimeout: .seconds(60))

    await #expect(throws: CancellationError.self) {
      try await cb.execute { throw CancellationError() }
    }
    #expect(await cb.canProceed())
  }
}

@Suite("NoopCircuitBreaker")
struct NoopCircuitBreakerTests {
  @Test("always proceeds regardless of failures")
  func alwaysProceeds() async throws {
    let cb = NoopCircuitBreaker()

    #expect(cb.canProceed())
    #expect(!cb.cannotProceed())
    cb.recordFailure()
    #expect(cb.canProceed())

    let result = try await cb.execute { "ok" }
    #expect(result == "ok")
  }
}
