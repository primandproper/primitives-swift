import Foundation
import Testing
import os

@testable import RateLimiting

/// A manually-driven monotonic ``Clock`` for deterministic refill tests, ported verbatim from
/// `CircuitBreakingTests.ManualClock`: it reuses ``ContinuousClock/Instant`` (so `Duration == Duration`
/// holds) and only advances when the test calls ``advance(by:)``, so token-bucket refill can be
/// exercised without sleeping in real time.
private final class ManualClock: Clock, @unchecked Sendable {
  typealias Instant = ContinuousClock.Instant
  typealias Duration = Swift.Duration

  private let state = OSAllocatedUnfairLock(initialState: ContinuousClock().now)

  var now: Instant { state.withLock { $0 } }
  var minimumResolution: Duration { .zero }

  func advance(by duration: Duration) {
    state.withLock { $0 = $0.advanced(by: duration) }
  }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    state.withLock { if deadline > $0 { $0 = deadline } }
  }
}

@Suite("TokenBucketRateLimiter")
struct TokenBucketRateLimiterTests {
  @Test("allows up to the burst size, then rejects")
  func allowsWithinBurst() async {
    let limiter = TokenBucketRateLimiter(
      requestsPerSecond: 10, burstSize: 3, clock: ManualClock())

    #expect(await limiter.allow(key: "user-1"))
    #expect(await limiter.allow(key: "user-1"))
    #expect(await limiter.allow(key: "user-1"))
    #expect(await !limiter.allow(key: "user-1"))
  }

  @Test("refills over injected time without sleeping")
  func refillsOverTime() async {
    let clock = ManualClock()
    let limiter = TokenBucketRateLimiter(requestsPerSecond: 10, burstSize: 1, clock: clock)

    #expect(await limiter.allow(key: "user-1"))
    #expect(await !limiter.allow(key: "user-1"))

    // At 10 tokens/sec, 100ms accrues exactly one token.
    clock.advance(by: .milliseconds(100))
    #expect(await limiter.allow(key: "user-1"))
    // The single accrued token was just spent; immediately asking again still fails.
    #expect(await !limiter.allow(key: "user-1"))
  }

  @Test("refill never exceeds the burst cap")
  func refillCapsAtBurst() async {
    let clock = ManualClock()
    let limiter = TokenBucketRateLimiter(requestsPerSecond: 100, burstSize: 2, clock: clock)

    // Drain the initial burst.
    #expect(await limiter.allow(key: "user-1"))
    #expect(await limiter.allow(key: "user-1"))
    #expect(await !limiter.allow(key: "user-1"))

    // A huge elapsed time would accrue far more than 2 tokens at 100/sec; the bucket must cap at
    // burstSize, so only 2 requests succeed, not more.
    clock.advance(by: .seconds(10))
    #expect(await limiter.allow(key: "user-1"))
    #expect(await limiter.allow(key: "user-1"))
    #expect(await !limiter.allow(key: "user-1"))
  }

  @Test("different keys have independent buckets")
  func perKeyIsolation() async {
    let limiter = TokenBucketRateLimiter(
      requestsPerSecond: 10, burstSize: 1, clock: ManualClock())

    #expect(await limiter.allow(key: "user-1"))
    #expect(await limiter.allow(key: "user-2"))
    #expect(await !limiter.allow(key: "user-1"))
    #expect(await !limiter.allow(key: "user-2"))
  }

  @Test("allow(key:count:) debits N tokens atomically, all-or-nothing")
  func allowNIsAtomic() async {
    let limiter = TokenBucketRateLimiter(
      requestsPerSecond: 10, burstSize: 5, clock: ManualClock())

    // Not enough tokens for a batch of 6; the bucket must be left untouched.
    #expect(await !limiter.allow(key: "batch", count: 6))
    // The full burst is still available for a batch of 5.
    #expect(await limiter.allow(key: "batch", count: 5))
    #expect(await !limiter.allow(key: "batch", count: 1))
  }

  @Test("allow(key:count:) with a non-positive count is always allowed and doesn't debit")
  func nonPositiveCountAlwaysAllowed() async {
    let limiter = TokenBucketRateLimiter(
      requestsPerSecond: 10, burstSize: 1, clock: ManualClock())

    #expect(await limiter.allow(key: "user-1", count: 0))
    #expect(await limiter.allow(key: "user-1", count: -1))
    // The bucket is still full: a real request still succeeds afterward.
    #expect(await limiter.allow(key: "user-1"))
  }

  @Test("availableTokens reports the refilled level without consuming it")
  func availableTokensInspection() async {
    let clock = ManualClock()
    let limiter = TokenBucketRateLimiter(requestsPerSecond: 10, burstSize: 3, clock: clock)

    #expect(await limiter.availableTokens(for: "user-1") == 3)
    #expect(await limiter.allow(key: "user-1"))
    #expect(await limiter.availableTokens(for: "user-1") == 2)
    // Inspecting again immediately doesn't change the level.
    #expect(await limiter.availableTokens(for: "user-1") == 2)
  }

  @Test("reset drops accumulated per-key state")
  func resetDropsBuckets() async {
    let limiter = TokenBucketRateLimiter(
      requestsPerSecond: 10, burstSize: 1, clock: ManualClock())

    #expect(await limiter.allow(key: "user-1"))
    #expect(await !limiter.allow(key: "user-1"))

    await limiter.reset()
    #expect(await limiter.allow(key: "user-1"))
  }
}
