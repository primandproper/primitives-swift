import Foundation
import Testing
import os

@testable import CircuitBreaking

/// Race-free call counter for `@Sendable` operation closures, which can't capture a mutable `var` under
/// strict concurrency.
private actor CallCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private struct Boom: Error {}

/// A manually-driven monotonic ``Clock`` for deterministic breaker timing tests (NET-12). Its instant
/// only advances when the test calls ``advance(by:)``, so open→half-open transitions can be exercised
/// without sleeping in real time. It reuses ``ContinuousClock/Instant`` so `Duration == Duration` holds
/// and never moves backward, honoring ``StandardCircuitBreaker``'s forward-only clock assumption.
private final class ManualClock: Clock, @unchecked Sendable {
  typealias Instant = ContinuousClock.Instant
  typealias Duration = Swift.Duration

  private let state = OSAllocatedUnfairLock(initialState: ContinuousClock().now)

  var now: Instant { state.withLock { $0 } }
  var minimumResolution: Duration { .zero }

  /// Advances the clock forward. The breaker only ever reads `now`; it never sleeps on this clock.
  func advance(by duration: Duration) {
    state.withLock { $0 = $0.advanced(by: duration) }
  }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    state.withLock { if deadline > $0 { $0 = deadline } }
  }
}

@Suite("StandardCircuitBreaker state machine")
struct StandardCircuitBreakerTests {
  /// A breaker that is effectively impossible to trip, for happy-path assertions.
  private func healthyBreaker() -> StandardCircuitBreaker<ContinuousClock> {
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

  @Test("re-opens on a failed trial even after the tripping samples have aged out of the window")
  func reopensOnHalfOpenFailureAfterWindowAgedOut() async throws {
    // Reproduces NET-01 under production-shaped timings: resetTimeout > window, so by the time the
    // half-open trial runs, the failures that first tripped the breaker have aged out of the rolling
    // window. With a sample threshold above 1, the lone trial failure can never reach shouldTrip via
    // the windowed-rate path, so before the fix the breaker stayed stuck half-open. Timings are kept
    // tiny (window 50ms, resetTimeout 120ms) to avoid large real sleeps; the actor has no injectable
    // clock yet, so a short real window is used to reproduce the aging-out deterministically.
    let cb = StandardCircuitBreaker(
      name: "aged", errorRatePercentage: 50, minimumSampleThreshold: 2,
      resetTimeout: .milliseconds(120), window: .milliseconds(50))

    await cb.recordFailure()
    await cb.recordFailure()  // two samples at 100% -> trips
    #expect(await cb.cannotProceed())

    // Past resetTimeout (120ms) so we are half-open, and well past the 50ms window so those two
    // failures have aged out.
    try await Task.sleep(for: .milliseconds(150))
    #expect(await cb.canProceed())  // half-open: a trial is allowed

    await cb.recordFailure()  // lone trial failure (total sample count 1 < threshold 2)
    #expect(await cb.cannotProceed())  // must re-trip regardless of the aged-out windowed rate
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

  @Test("execute rethrows a cancelled URLError without counting it as a failure")
  func executeIgnoresURLErrorCancelled() async {
    // NET-07: a cancelled URLSession request surfaces as URLError.cancelled, not CancellationError.
    // execute must treat it as cancellation (consistent with HTTPClient) and not record a breaker
    // failure. Rate 1% at 1 sample would trip on any single real failure; this must not be one.
    let cb = StandardCircuitBreaker(
      name: "urlcancel", errorRatePercentage: 1, minimumSampleThreshold: 1, resetTimeout: .seconds(60))

    await #expect(throws: URLError.self) {
      try await cb.execute { throw URLError(.cancelled) }
    }
    #expect(await cb.canProceed())
  }

  @Test("an injected manual clock drives the open→half-open transition without real sleeping")
  func manualClockDrivesHalfOpenTransition() async {
    // NET-12: with the clock injected, elapsed time is fully under the test's control — no Task.sleep.
    let clock = ManualClock()
    let cb = StandardCircuitBreaker(
      name: "manual", errorRatePercentage: 50, minimumSampleThreshold: 1,
      resetTimeout: .seconds(30), clock: clock)

    await cb.recordFailure()  // 100% over 1 sample -> trips open
    #expect(await cb.cannotProceed())

    // Still within the 30s reset window: the breaker stays open.
    clock.advance(by: .seconds(10))
    #expect(await cb.cannotProceed())

    // Past the reset timeout (total 31s): the breaker is half-open and allows a trial.
    clock.advance(by: .seconds(21))
    #expect(await cb.canProceed())

    // A successful trial closes it again — driven entirely by the manual clock.
    await cb.recordSuccess()
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
