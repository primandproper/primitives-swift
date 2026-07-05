/// A ``RetryPolicy`` with configurable exponential backoff and optional jitter, ported from
/// platform-go's unexported `exponentialBackoff` (constructed via `NewExponentialBackoffPolicy`).
///
/// Go hides the implementation behind the `Policy` interface and a constructor function; Swift exposes a
/// public `struct` with a plain initializer, which is both idiomatic and cheap to value-copy (the type
/// is immutable and `Sendable`). The initializer applies ``RetryConfig/ensureDefaults()`` up front, so a
/// zero-valued or nonsensical config can never yield a pathological policy — exactly as the Go
/// constructor does.
public struct ExponentialBackoffPolicy: RetryPolicy {
  /// The effective config, already defaulted and clamped.
  public let config: RetryConfig

  public init(config: RetryConfig) {
    self.config = config.ensuringDefaults()
  }

  /// Runs `operation`, retrying up to ``RetryConfig/maxAttempts`` times with exponential backoff.
  ///
  /// Behavioral parity with Go's `Execute`:
  /// - A successful attempt returns its value immediately.
  /// - A terminal error (``UnretryableError`` or `CancellationError`) short-circuits the loop instead of
  ///   sleeping and burning the remaining attempts — see ``isTerminal(_:)``.
  /// - After the final attempt, the last thrown error is rethrown.
  ///
  /// **Cancellation.** Go's per-loop `select { case <-ctx.Done(): … }` becomes structured-concurrency
  /// cancellation: `Task.checkCancellation()` at the top of each attempt aborts before running the
  /// operation if the surrounding task is cancelled, and `Task.sleep` throws `CancellationError` if the
  /// task is cancelled mid-backoff. Either way the loop unwinds by throwing `CancellationError`, the
  /// Swift analogue of Go returning `context.Canceled`.
  ///
  /// **Jitter guard.** When ``RetryConfig/useJitter`` is on, the delay is randomized within
  /// `[delay/2, delay)`. Following Go, the half-delay is computed in whole nanoseconds; if it truncates
  /// to zero (a sub-2ns delay), jitter is skipped rather than feeding `0` to the random generator — Go
  /// skips it to avoid `rand.Int64N(0)` panicking, and Swift skips it to avoid an empty `0..<0` range.
  public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    var lastError: (any Error)?
    var delay = config.initialDelay
    let maxAttempts = config.maxAttempts

    for attempt in 0..<maxAttempts {
      try Task.checkCancellation()

      do {
        return try await operation()
      } catch {
        lastError = error

        // A terminal error can never be resolved by another attempt — rethrow instead of sleeping.
        if isTerminal(error) {
          throw error
        }

        // No point sleeping after the last attempt.
        if attempt == maxAttempts - 1 {
          break
        }

        var sleepDuration = delay
        // The half-delay is truncated to whole nanoseconds (as Go does); when it's zero the delay is
        // too small to halve, so jitter is skipped and the full delay is used.
        if config.useJitter {
          let halfNanos = delay.wholeNanoseconds / 2
          if halfNanos > 0 {
            let jitter = Int64.random(in: 0..<halfNanos)
            sleepDuration = delay - .nanoseconds(halfNanos) + .nanoseconds(jitter)
          }
        }

        try await Task.sleep(for: sleepDuration)

        // delay = min(delay * multiplier, maxDelay), computed in nanoseconds like Go, with the cap
        // applied before the Int64 conversion so a large multiplier can't overflow.
        let scaledNanos = Double(delay.wholeNanoseconds) * config.multiplier
        let cappedNanos = min(scaledNanos, Double(config.maxDelay.wholeNanoseconds))
        delay = .nanoseconds(Int64(cappedNanos))
      }
    }

    // Unreachable while maxAttempts >= 1 (guaranteed by ensureDefaults): the loop always returns on
    // success or throws/breaks on failure with lastError set. The fallback exists only to satisfy the
    // type checker for a hypothetical zero-attempt config.
    throw lastError ?? CancellationError()
  }
}
