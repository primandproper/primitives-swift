import Foundation

/// Executes an operation with retry logic, ported from platform-go's `retry.Policy` interface.
///
/// Go's `Execute(ctx, func(ctx) error) error` becomes a generic `async throws` method: the operation is
/// a `@Sendable` async closure and its result flows back to the caller, so retrying can wrap a call that
/// *produces a value*, not just one that reports success/failure. Go's `context.Context` argument is
/// gone — Swift structured concurrency carries cancellation implicitly, and the operation is expected to
/// honor it (see ``ExponentialBackoffPolicy/execute(_:)`` for how cancellation maps to Go's terminal
/// `context.Canceled`).
public protocol RetryPolicy: Sendable {
  /// Runs `operation`, retrying on thrown errors per the policy. Returns the operation's value on
  /// success; rethrows the final error (or a terminal one) on failure.
  func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T
}

/// Marks an error as one the retry loop must not retry, ported from platform-go's `retry.ErrUnretryable`
/// sentinel and its `Unretryable(err)` wrapper.
///
/// Go wraps the sentinel into the error chain and detects it with `errors.Is`; Swift has no error chain,
/// so this is a concrete wrapper type. Throwing `UnretryableError(someError)` from an operation stops
/// ``ExponentialBackoffPolicy`` immediately instead of exhausting the remaining attempts. The original
/// error is preserved in ``underlying`` for the caller to inspect.
///
/// Go's `Unretryable(nil)` returns `nil`; the Swift analogue is simply not throwing — there is no error
/// to wrap.
public struct UnretryableError: Error {
  /// The error being marked non-retryable.
  public let underlying: any Error

  public init(_ underlying: any Error) {
    self.underlying = underlying
  }
}

/// Reports whether an error should abort the retry loop rather than trigger another attempt, mirroring
/// Go's `isTerminal`.
///
/// Go treats a canceled/expired `context.Context` and an `ErrUnretryable`-wrapped error as terminal. The
/// Swift equivalents are `CancellationError` (thrown by `Task.checkCancellation()` / `Task.sleep` and,
/// by convention, by cancellation-aware operations) and ``UnretryableError``. A `URLSession` request torn
/// down by task cancellation surfaces the cancellation as `URLError.cancelled` rather than
/// `CancellationError` (see `HTTPClient`, which deliberately leaves it unwrapped for this check), so that
/// too is terminal. None can be resolved by waiting and trying again, so the loop returns immediately.
func isTerminal(_ error: any Error) -> Bool {
  error is CancellationError || error is UnretryableError || (error as? URLError)?.code == .cancelled
}
