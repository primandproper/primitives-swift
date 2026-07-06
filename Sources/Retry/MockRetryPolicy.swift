/// A recording ``RetryPolicy`` test double: it counts how many times ``execute(_:)`` was invoked and
/// re-runs the operation up to a configurable number of attempts, so a test can both assert the policy
/// was consulted and drive the retry-on-throw path of the code-under-test. The Mock counterpart to
/// ``NoopRetryPolicy`` under REPO-05 (every seam ships a Noop and a Mock).
///
/// An `actor` so the call counter is race-free under concurrency, matching the other port recorders.
public actor MockRetryPolicy: RetryPolicy {
  /// The maximum number of times a single ``execute(_:)`` will run the operation before giving up.
  private let attempts: Int

  /// How many times ``execute(_:)`` has been called (not how many attempts ran within them).
  public private(set) var executeCallCount = 0

  /// The total number of operation attempts across all ``execute(_:)`` calls.
  public private(set) var attemptCount = 0

  /// - Parameter attempts: the max operation runs per ``execute(_:)`` (clamped to at least 1). Default 1
  ///   makes it a pass-through like ``NoopRetryPolicy`` but with call recording.
  public init(attempts: Int = 1) {
    self.attempts = max(1, attempts)
  }

  public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    executeCallCount += 1
    var lastError: (any Error)?
    for _ in 0..<attempts {
      attemptCount += 1
      do {
        return try await operation()
      } catch {
        lastError = error
      }
    }
    // attempts >= 1, so the loop ran at least once; reaching here means every run threw.
    throw lastError!
  }
}
