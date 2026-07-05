/// A ``CircuitBreaker`` that always allows operations to proceed — ported from platform-go's
/// `circuitbreaking/noop` subpackage.
///
/// Go isolates the no-op in its own package to dodge an import cycle with the interface; Swift has no
/// such pressure, so it folds into the `CircuitBreaking` module as a plain, stateless `struct`. It is
/// the always-safe fallback returned when configuration is invalid or a breaker is disabled — matching
/// Go's `EnsureCircuitBreaker(nil)`, which logs and hands back a no-op rather than a `nil` breaker.
///
/// Because it holds no state it is trivially `Sendable`, and its synchronous method bodies satisfy the
/// protocol's `async` requirements.
public struct NoopCircuitBreaker: CircuitBreaker {
  public init() {}

  public func recordFailure() {}
  public func recordSuccess() {}
  public func canProceed() -> Bool { true }
  public func cannotProceed() -> Bool { false }
}
