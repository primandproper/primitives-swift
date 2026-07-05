/// A ``RetryPolicy`` that runs the operation exactly once with no retries, ported from platform-go's
/// `retry/noop` subpackage.
///
/// Go isolates the no-op in its own package; Swift folds it into the `Retry` module as a distinct type,
/// since there's no import-cycle or naming pressure forcing a separate module. Use it as the always-safe
/// pass-through wherever a `RetryPolicy` is required but retrying is undesired (e.g. tests, or callers
/// that manage their own retries).
public struct NoopRetryPolicy: RetryPolicy {
  public init() {}

  /// Runs the operation once and returns (or rethrows) its result verbatim.
  public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    try await operation()
  }
}
