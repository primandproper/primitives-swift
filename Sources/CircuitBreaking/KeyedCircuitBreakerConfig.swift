import Observability

/// Configuration for a partitioned (keyed) circuit breaker, ported from platform-go's
/// `partitionedcfg.Config`.
///
/// It composes a ``CircuitBreakerConfig`` (`base`) — the shared shape every per-key breaker is built
/// from — with the fixed set of `keys` that each get a dedicated breaker. The JSON coding keys match
/// Go's (`circuitBreakerKeys`, `base`), and defaulting delegates to the base config.
public struct KeyedCircuitBreakerConfig: Codable, Sendable, Equatable {
  /// The keys that each receive a dedicated breaker; every other key shares the global fallback.
  public var keys: [String]
  /// The shape all per-key breakers (and the global fallback) are built from.
  public var base: CircuitBreakerConfig

  /// The metric tag key distinguishing breakers that share counter names — Go's `partitionAttributeKey`.
  static let partitionTagKey = "partition"
  /// The tag value for the shared fallback breaker — Go's `globalPartition`.
  static let globalPartition = "global"

  public init(keys: [String] = [], base: CircuitBreakerConfig = .init()) {
    self.keys = keys
    self.base = base
  }

  /// Fills defaults, delegating to the base config. Mirrors Go's `EnsureDefaults`.
  public mutating func ensureDefaults() {
    base.ensureDefaults()
  }

  /// A copy with ``ensureDefaults()`` applied.
  public func ensuringDefaults() -> KeyedCircuitBreakerConfig {
    var copy = self
    copy.ensureDefaults()
    return copy
  }

  /// Validates the base config and requires every key to be non-empty. Mirrors Go's
  /// `ValidateWithContext` (base validation, then `validation.Each(Required)` over the keys).
  public func validate() throws {
    try base.validate()
    if keys.contains(where: \.isEmpty) {
      throw KeyedCircuitBreakerConfigError.emptyKey
    }
  }

  /// Builds a live ``KeyedCircuitBreaker`` — the port of Go's `ProvideKeyedCircuitBreaker`.
  ///
  /// A dedicated breaker is built for each key (tagged `partition: <key>`) plus one shared global
  /// breaker (tagged `partition: global`), so breakers that share counter names stay distinguishable in
  /// metrics. An invalid config degrades to ``NoopKeyedCircuitBreaker`` (logged), matching Go.
  ///
  /// Go validated *before* defaulting here (unlike the single-breaker path), so an out-of-range base
  /// config short-circuits to the no-op keyed breaker; the port preserves that ordering.
  public func provideKeyedCircuitBreaker(
    logger: any Logger = NoopLogger(),
    metrics: any MetricsProvider = NoopMetricsProvider(),
    resetTimeout: Duration = StandardCircuitBreaker<ContinuousClock>.defaultResetTimeout
  ) -> any KeyedCircuitBreaker {
    do {
      try validate()
    } catch {
      logger.error("invalid config passed, providing noop keyed circuit breaker", error)
      return NoopKeyedCircuitBreaker()
    }

    let defaulted = base.ensuringDefaults()

    let global = defaulted.provideCircuitBreaker(
      logger: logger,
      metrics: metrics,
      tags: [Self.partitionTagKey: Self.globalPartition],
      resetTimeout: resetTimeout)

    var breakers: [String: any CircuitBreaker] = [:]
    breakers.reserveCapacity(keys.count)
    for key in keys {
      breakers[key] = defaulted.provideCircuitBreaker(
        logger: logger,
        metrics: metrics,
        tags: [Self.partitionTagKey: key],
        resetTimeout: resetTimeout)
    }

    return PartitionedCircuitBreaker(global: global, breakers: breakers)
  }

  private enum CodingKeys: String, CodingKey {
    case keys = "circuitBreakerKeys"
    case base
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
    base = try c.decodeIfPresent(CircuitBreakerConfig.self, forKey: .base) ?? .init()
  }
}

/// A rejected ``KeyedCircuitBreakerConfig``.
public enum KeyedCircuitBreakerConfigError: Error, Equatable {
  /// One of the configured keys was empty.
  case emptyKey
}
