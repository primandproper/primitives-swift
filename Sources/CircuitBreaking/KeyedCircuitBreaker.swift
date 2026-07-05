/// Hands out an independent ``CircuitBreaker`` per registered key — ported from platform-go's
/// `partitioned.KeyedCircuitBreaker`.
///
/// Where a single breaker shares one health signal across all traffic, a keyed breaker isolates it: a
/// key registered at construction (say, a tenant ID) gets its own breaker and can be circuit-broken
/// without affecting anyone else, while any unregistered key falls back to a shared global breaker. The
/// set of keys is fixed and operator-chosen, keeping per-breaker metric cardinality low.
///
/// Go's method is `For(key)`; the Swift port spells it `breaker(for:)` — the idiomatic argument-label
/// form, and one that sidesteps `for` being a reserved keyword at call sites.
public protocol KeyedCircuitBreaker: Sendable {
  /// Returns the dedicated breaker registered for `key`, or the shared global breaker when `key` was
  /// not registered.
  func breaker(for key: String) -> any CircuitBreaker
}

/// A ``KeyedCircuitBreaker`` backed by a fixed map of dedicated breakers plus a shared global fallback —
/// the port of Go's `keyedBreaker`.
///
/// **Why a struct, not an actor.** The Go type carried an `RWMutex`, but the map is populated once at
/// construction and never mutated afterward — the lock guarded reads of immutable data. The idiomatic,
/// zero-overhead Swift shape is therefore an immutable `struct` holding a `let` map: it is `Sendable`
/// because its stored breakers are `Sendable`, and ``breaker(for:)`` stays synchronous (no needless
/// `async` hop just to index a dictionary). The real mutable state lives one level down, inside each
/// ``StandardCircuitBreaker`` actor, which is where the concurrency safety belongs. Modeling this as an
/// actor would add a serialization point that protects nothing.
public struct PartitionedCircuitBreaker: KeyedCircuitBreaker {
  private let global: any CircuitBreaker
  private let breakers: [String: any CircuitBreaker]

  /// Serves each key in `breakers` from its dedicated breaker and every other key from `global`.
  public init(global: any CircuitBreaker, breakers: [String: any CircuitBreaker] = [:]) {
    self.global = global
    self.breakers = breakers
  }

  public func breaker(for key: String) -> any CircuitBreaker {
    breakers[key] ?? global
  }
}

/// A ``KeyedCircuitBreaker`` that hands the same always-proceed ``NoopCircuitBreaker`` to every key —
/// ported from `partitioned/noop`. The always-safe fallback for invalid config or a disabled breaker.
public struct NoopKeyedCircuitBreaker: KeyedCircuitBreaker {
  private let inner: any CircuitBreaker

  public init() {
    self.inner = NoopCircuitBreaker()
  }

  public func breaker(for _: String) -> any CircuitBreaker {
    inner
  }
}
