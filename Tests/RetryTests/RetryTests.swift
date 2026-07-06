import Foundation
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

/// A transient error carrying a ``RetryDelayFloor`` — the retry-side stand-in for a `429`/`503` whose
/// `Retry-After` header the policy must honor as a delay floor.
private struct FloorError: Error, RetryDelayFloor {
  let retryAfterFloor: Duration?
}

/// Records the durations the injected sleeper was asked to wait, so floor behavior is asserted on the
/// exact schedule rather than on wall-clock time.
private actor SleepRecorder {
  private(set) var durations: [Duration] = []
  func record(_ duration: Duration) { durations.append(duration) }
}

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

  // Regression (NET-06): a URLSession request cancelled by task teardown surfaces as
  // `URLError.cancelled`, not `CancellationError`. `isTerminal` must treat it as terminal so the loop
  // short-circuits immediately instead of relying on the next `Task.sleep` to unwind it. Without the fix
  // this would burn all 5 attempts.
  @Test("a URLError.cancelled from the operation short-circuits the loop")
  func terminalURLErrorCancelledShortCircuits() async {
    let policy = fastPolicy(maxAttempts: 5)
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        throw URLError(.cancelled)
      }
    } catch {
      thrown = error
    }

    #expect((thrown as? URLError)?.code == .cancelled)
    #expect(await counter.count == 1)
  }

  // A non-cancellation URLError (e.g. a transient network drop) is not terminal and must still be
  // retried — guards against `isTerminal` over-matching on URLError as a whole.
  @Test("a non-cancellation URLError is retried, not treated as terminal")
  func nonCancellationURLErrorIsRetried() async {
    let policy = fastPolicy(maxAttempts: 3)
    let counter = Counter()
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in
        await counter.increment()
        throw URLError(.networkConnectionLost)
      }
    } catch {
      thrown = error
    }

    #expect((thrown as? URLError)?.code == .networkConnectionLost)
    #expect(await counter.count == 3)
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

  @Test("cancelling the surrounding task aborts the retry loop instead of waiting out the backoff")
  func respectsTaskCancellation() async {
    // A long initial delay means that, absent cancellation, this would block for an hour. Cancelling
    // must unwind it promptly by throwing (the surfaced error is covered by cancellationSurfacesLastError).
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(maxAttempts: 10, initialDelay: .seconds(3600), useJitter: false))

    let task = Task { () async throws -> Int in
      try await policy.execute { throw TransientError() }
    }
    task.cancel()

    await #expect(throws: (any Error).self) {
      _ = try await task.value
    }
  }

  // NET-24: matching Go's `case <-ctx.Done(): return lastErr`, a cancellation landing mid-backoff must
  // surface the *last operation error* (so the caller learns why the work was failing), not a bare
  // CancellationError. Injecting a sleeper that throws makes the mid-backoff cancellation deterministic.
  @Test("cancellation mid-backoff surfaces the last operation error, not a bare CancellationError")
  func cancellationSurfacesLastError() async {
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(maxAttempts: 5, initialDelay: .nanoseconds(1)),
      sleep: { _ in throw CancellationError() })
    var thrown: (any Error)?

    do {
      _ = try await policy.execute { () async throws -> Int in throw FinalError(id: 7) }
    } catch {
      thrown = error
    }

    #expect(thrown as? FinalError == FinalError(id: 7))
  }

  // NET-24: a RetryDelayFloor (the retry analogue of Retry-After) raises the next backoff to at least the
  // floor when the floor exceeds the computed delay.
  @Test("a RetryDelayFloor error raises the next backoff to at least the floor")
  func retryAfterFloorRaisesBackoff() async {
    let recorder = SleepRecorder()
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(
        maxAttempts: 2, initialDelay: .nanoseconds(1), maxDelay: .nanoseconds(10), multiplier: 2,
        useJitter: false),
      sleep: { await recorder.record($0) })

    _ = try? await policy.execute { () async throws -> Int in
      throw FloorError(retryAfterFloor: .seconds(5))
    }

    // The 5s floor wins over the 1ns exponential backoff for the single inter-attempt wait.
    #expect(await recorder.durations == [.seconds(5)])
  }

  // The original suite only counts attempts; these pin the actual delay *schedule* via the injected
  // sleeper, so a regression in the geometric progression, the cap, or the jitter bounds is caught.
  @Test("without jitter the inter-attempt delays follow the geometric progression")
  func geometricProgressionWithoutJitter() async {
    let recorder = SleepRecorder()
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(
        maxAttempts: 5, initialDelay: .milliseconds(100), maxDelay: .seconds(100), multiplier: 2,
        useJitter: false),
      sleep: { await recorder.record($0) })

    _ = try? await policy.execute { () async throws -> Int in throw TransientError() }

    // 5 attempts -> 4 inter-attempt sleeps (none after the final attempt); each is the previous doubled,
    // and the 100s cap is never reached.
    #expect(
      await recorder.durations == [
        .milliseconds(100), .milliseconds(200), .milliseconds(400), .milliseconds(800),
      ])
  }

  @Test("the per-attempt delay is clamped at maxDelay")
  func delayClampedAtMaxDelay() async {
    let recorder = SleepRecorder()
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(
        maxAttempts: 5, initialDelay: .milliseconds(100), maxDelay: .milliseconds(500),
        multiplier: 10,
        useJitter: false),
      sleep: { await recorder.record($0) })

    _ = try? await policy.execute { () async throws -> Int in throw TransientError() }

    // 100ms, then 100*10 = 1000ms clamped down to the 500ms ceiling, and every later delay pinned there.
    #expect(
      await recorder.durations == [
        .milliseconds(100), .milliseconds(500), .milliseconds(500), .milliseconds(500),
      ])
  }

  @Test("with jitter every delay stays within the documented [delay/2, delay) bounds")
  func jitterStaysWithinBounds() async {
    let recorder = SleepRecorder()
    // multiplier 1 holds the base delay constant at 100ms every attempt (it isn't clamped — the clamp is
    // multiplier < 1), so each recorded sleep must land in [50ms, 100ms): the policy computes
    // `delay - (delay/2 whole-ns) + random(0..<(delay/2 whole-ns))`.
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(
        maxAttempts: 20, initialDelay: .milliseconds(100), maxDelay: .seconds(1), multiplier: 1,
        useJitter: true),
      sleep: { await recorder.record($0) })

    _ = try? await policy.execute { () async throws -> Int in throw TransientError() }

    let durations = await recorder.durations
    #expect(durations.count == 19)  // 20 attempts -> 19 inter-attempt sleeps
    for delay in durations {
      #expect(delay >= .milliseconds(50))  // lower bound, hit when the random draw is 0
      // strict upper bound: jitter never reaches the full delay
      #expect(delay < .milliseconds(100))
    }
  }

  // NET-24: a floor smaller than the computed backoff is a no-op — the normal exponential schedule wins.
  @Test("a floor below the computed backoff leaves the backoff untouched")
  func retryAfterFloorBelowBackoffIgnored() async {
    let recorder = SleepRecorder()
    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(
        maxAttempts: 2, initialDelay: .seconds(2), maxDelay: .seconds(10), multiplier: 2,
        useJitter: false),
      sleep: { await recorder.record($0) })

    _ = try? await policy.execute { () async throws -> Int in
      throw FloorError(retryAfterFloor: .milliseconds(1))
    }

    #expect(await recorder.durations == [.seconds(2)])
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
