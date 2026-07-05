import Testing

@testable import Retry

/// Serial attempt counter. The operation closure is `@Sendable`, so it can't capture a mutable `var`
/// under strict concurrency; an actor gives it a safe, race-free counter. (execute runs attempts
/// serially, so there's no real contention.)
private actor Counter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private struct TransientError: Error {}
private struct FinalError: Error, Equatable { let id: Int }
private struct Underlying: Error, Equatable {}

@Suite("ExponentialBackoffPolicy.execute")
struct ExponentialBackoffPolicyTests {
  /// Tiny, non-zero delays so nothing actually waits. Non-zero matters: a zero initialDelay would be
  /// replaced with the 100ms default by ensureDefaults and slow the suite down.
  private func fastPolicy(maxAttempts: UInt, useJitter: Bool = false) -> ExponentialBackoffPolicy {
    ExponentialBackoffPolicy(
      config: RetryConfig(
        maxAttempts: maxAttempts, initialDelay: .nanoseconds(1), maxDelay: .nanoseconds(10),
        multiplier: 2.0, useJitter: useJitter))
  }

  @Test("success on the first attempt runs the operation once and returns its value")
  func successFirstAttempt() async throws {
    let policy = fastPolicy(maxAttempts: 3)
    let counter = Counter()

    let result = try await policy.execute {
      await counter.increment()
      return "ok"
    }

    #expect(result == "ok")
    #expect(await counter.count == 1)
  }

  @Test("succeeds after N transient failures")
  func successAfterRetries() async throws {
    let policy = fastPolicy(maxAttempts: 5)
    let counter = Counter()

    let result = try await policy.execute { () async throws -> Int in
      await counter.increment()
      if await counter.count < 3 {
        throw TransientError()
      }
      return 42
    }

    #expect(result == 42)
    #expect(await counter.count == 3)
  }

  @Test("exhausting the attempts rethrows the last error")
  func exhaustsAttempts() async {
    let policy = fastPolicy(maxAttempts: 3)
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        if await counter.count < 3 {
          throw TransientError()
        }
        throw FinalError(id: 99)
      }
    } catch {
      thrown = error
    }

    #expect(thrown as? FinalError == FinalError(id: 99))
    #expect(await counter.count == 3)
  }

  @Test("a terminal CancellationError from the operation short-circuits the loop")
  func terminalCancellationShortCircuits() async {
    let policy = fastPolicy(maxAttempts: 5)
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        throw CancellationError()
      }
    } catch {
      thrown = error
    }

    #expect(thrown is CancellationError)
    // Retrying a cancellation is pointless; it must not burn all 5 attempts.
    #expect(await counter.count == 1)
  }

  @Test("an UnretryableError stops immediately and preserves the underlying error")
  func unretryableStopsImmediately() async throws {
    let policy = fastPolicy(maxAttempts: 5)
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        throw UnretryableError(Underlying())
      }
    } catch {
      thrown = error
    }

    let unretryable = try #require(thrown as? UnretryableError)
    #expect(unretryable.underlying as? Underlying == Underlying())
    #expect(await counter.count == 1)
  }

  // Regression: a sub-2ns delay makes the whole-nanosecond half-delay truncate to 0. Jitter must be
  // skipped rather than fed to `Int64.random(in: 0..<0)`, which would trap.
  @Test("jitter does not crash when the delay is too small to halve")
  func jitterTinyDelayDoesNotCrash() async {
    let policy = fastPolicy(maxAttempts: 3, useJitter: true)  // initialDelay is 1ns → half is 0ns
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        throw TransientError()
      }
    } catch {
      thrown = error
    }

    #expect(thrown is TransientError)
    #expect(await counter.count == 3)
  }

  @Test("cancelling the surrounding task aborts the retry loop")
  func respectsTaskCancellation() async {
    // A long initial delay guarantees the cancellation lands during backoff, whichever attempt is
    // in flight, and surfaces as a thrown CancellationError.
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(maxAttempts: 10, initialDelay: .seconds(3600), useJitter: false))

    let task = Task { () async throws -> Int in
      try await policy.execute { throw TransientError() }
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
  }
}

@Suite("NoopRetryPolicy.execute")
struct NoopRetryPolicyTests {
  @Test("runs exactly once on success and returns the value")
  func onceOnSuccess() async throws {
    let policy = NoopRetryPolicy()
    let counter = Counter()

    let result = try await policy.execute {
      await counter.increment()
      return "value"
    }

    #expect(result == "value")
    #expect(await counter.count == 1)
  }

  @Test("runs exactly once on failure and rethrows")
  func onceOnFailure() async {
    let policy = NoopRetryPolicy()
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        throw FinalError(id: 1)
      }
    } catch {
      thrown = error
    }

    #expect(thrown as? FinalError == FinalError(id: 1))
    #expect(await counter.count == 1)
  }
}
