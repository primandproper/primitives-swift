import os

/// A recording ``CircuitBreaker`` test double: it counts ``recordFailure()`` / ``recordSuccess()`` /
/// ``canProceed()`` calls and answers ``canProceed()`` from an injectable, mutable flag, so a test can
/// both assert the breaker was reported to *and* force the open/closed decision. The Mock counterpart to
/// ``NoopCircuitBreaker`` under REPO-05 (every seam ships a Noop and a Mock).
///
/// An `actor` so its counters and gate flag are race-free — matching ``StandardCircuitBreaker``'s
/// isolation model — and so its synchronous-looking bodies satisfy the protocol's `async` requirements.
public actor MockCircuitBreaker: CircuitBreaker {
  public private(set) var recordFailureCallCount = 0
  public private(set) var recordSuccessCallCount = 0
  public private(set) var canProceedCallCount = 0
  private var proceed: Bool

  /// - Parameter canProceed: the initial gate answer (default `true`, i.e. closed/healthy).
  public init(canProceed: Bool = true) {
    self.proceed = canProceed
  }

  /// Flips the gate answer subsequent ``canProceed()`` calls return, letting a test trip or reset the
  /// mock mid-run.
  public func setCanProceed(_ value: Bool) {
    proceed = value
  }

  public func recordFailure() {
    recordFailureCallCount += 1
  }

  public func recordSuccess() {
    recordSuccessCallCount += 1
  }

  public func canProceed() -> Bool {
    canProceedCallCount += 1
    return proceed
  }
}

/// A recording ``KeyedCircuitBreaker`` test double: it captures every key passed to ``breaker(for:)`` in
/// ``requestedKeys`` and returns an injectable inner breaker (default ``NoopCircuitBreaker``). The Mock
/// counterpart to ``NoopKeyedCircuitBreaker`` under REPO-05.
///
/// A lock-backed `final class` rather than an `actor`: ``KeyedCircuitBreaker/breaker(for:)`` is a
/// *synchronous* requirement (an actor's methods are `async` and couldn't satisfy it), so a lock guards
/// the recorded keys instead.
public final class MockKeyedCircuitBreaker: KeyedCircuitBreaker, @unchecked Sendable {
  private let inner: any CircuitBreaker
  private let recorded = OSAllocatedUnfairLock(initialState: [String]())

  /// The keys handed to ``breaker(for:)``, in call order.
  public var requestedKeys: [String] { recorded.withLock { $0 } }

  /// - Parameter breaker: the breaker every key resolves to (default ``NoopCircuitBreaker``).
  public init(breaker: any CircuitBreaker = NoopCircuitBreaker()) {
    self.inner = breaker
  }

  public func breaker(for key: String) -> any CircuitBreaker {
    recorded.withLock { $0.append(key) }
    return inner
  }
}
