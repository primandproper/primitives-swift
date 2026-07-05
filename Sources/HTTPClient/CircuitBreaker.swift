/// A minimal circuit-breaker contract that ``HTTPClient`` gates requests through, mirroring
/// platform-go's `circuitbreaking.CircuitBreaker` interface.
///
/// **Why a local protocol, not a dependency on the `CircuitBreaking` module.** That module is being
/// written concurrently and its final Swift API isn't settled, so hard-linking to it now would couple
/// this port to an unstable surface. Instead the dependency is modeled *loosely*: this protocol
/// restates the small Go interface, and a breaker is injected as an optional. When the real
/// `CircuitBreaking` module lands, its breaker type conforms to (or is adapted onto) this protocol at
/// the wiring site — no change to ``HTTPClient`` itself.
///
/// The Go interface is method-for-method:
///
/// ```go
/// type CircuitBreaker interface {
///   Failed()
///   Succeeded()
///   CanProceed() bool
///   CannotProceed() bool
/// }
/// ```
///
/// `CannotProceed()` is given a default implementation here since it is always the negation of
/// `canProceed()`; a conformer may still override it (Go declares both explicitly).
public protocol CircuitBreaker: Sendable {
  /// Record a failed operation. Repeated failures are what trip the breaker open.
  func failed()
  /// Record a successful operation, moving the breaker back toward closed.
  func succeeded()
  /// Whether an operation may proceed (the circuit is closed or half-open).
  func canProceed() -> Bool
  /// Whether an operation must be refused (the circuit is open).
  func cannotProceed() -> Bool
}

extension CircuitBreaker {
  public func cannotProceed() -> Bool { !canProceed() }
}

/// A breaker that never trips, ported from platform-go's `circuitbreaking/noop`. Use it where a
/// breaker is required but the behavior isn't wanted (tests, or callers opting out of breaking).
public struct NoopCircuitBreaker: CircuitBreaker {
  public init() {}
  public func failed() {}
  public func succeeded() {}
  public func canProceed() -> Bool { true }
}
