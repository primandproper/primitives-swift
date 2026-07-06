import Observability

/// Configuration for a single ``CircuitBreaker``, ported from platform-go's `circuitbreakingcfg.Config`.
///
/// Go tags each field with `env:` (environment) and `json:`. Per the settled port architecture, iOS apps
/// don't configure from the environment, so only the JSON contract survives — the coding keys match
/// Go's exactly (`name`, `circuitBreakerErrorPercentage`, `circuitBreakerMinimumOccurrenceThreshold`) so
/// a config authored for a Go peer round-trips unchanged.
///
/// Defaults mirror Go's `EnsureDefaults` verbatim: an unset name becomes `"UNKNOWN"`, a zero error rate
/// becomes `100`, and a zero sample threshold becomes `20`.
public struct CircuitBreakerConfig: Codable, Sendable, Equatable {
  /// Names the breaker in logs/metrics. Empty defaults to `"UNKNOWN"`.
  public var name: String
  /// Trip threshold as a percentage (0–100). Zero defaults to `100`.
  public var errorRate: Double
  /// Minimum windowed samples before the error rate is evaluated. Zero defaults to `20`.
  public var minimumSampleThreshold: UInt64

  static let defaultName = "UNKNOWN"
  static let defaultErrorRate: Double = 100
  static let defaultMinimumSampleThreshold: UInt64 = 20

  public init(name: String = "", errorRate: Double = 0, minimumSampleThreshold: UInt64 = 0) {
    self.name = name
    self.errorRate = errorRate
    self.minimumSampleThreshold = minimumSampleThreshold
  }

  /// Fills unset fields with Go's defaults. Mirrors `Config.EnsureDefaults`.
  public mutating func ensureDefaults() {
    if name.isEmpty {
      name = Self.defaultName
    }
    if errorRate == 0 {
      errorRate = Self.defaultErrorRate
    }
    if minimumSampleThreshold == 0 {
      minimumSampleThreshold = Self.defaultMinimumSampleThreshold
    }
  }

  /// A copy with ``ensureDefaults()`` applied.
  public func ensuringDefaults() -> CircuitBreakerConfig {
    var copy = self
    copy.ensureDefaults()
    return copy
  }

  /// Validates the config, mirroring Go's `ValidateWithContext` (name required, error rate in 0…100).
  public func validate() throws {
    if name.isEmpty {
      throw CircuitBreakerConfigError.missingName
    }
    if errorRate < 0 || errorRate > 100 {
      throw CircuitBreakerConfigError.errorRateOutOfRange(errorRate)
    }
  }

  /// Builds a live ``CircuitBreaker`` from this config — the port of Go's `ProvideCircuitBreaker`.
  ///
  /// Defaults are applied **before** validation, exactly as the Go origin does: otherwise the common
  /// case of an unset name would fail the required-name check and silently degrade to a no-op breaker —
  /// protection that looks wired but does nothing. With defaults first, the `"UNKNOWN"` name passes and
  /// a real breaker is returned. Only a genuinely out-of-range error rate degrades to
  /// ``NoopCircuitBreaker`` (logged), matching Go's "invalid config → noop" behavior.
  ///
  /// Unlike Go this does not throw: Go's error path was metric-instrument creation failing, which the
  /// swift-metrics surface can't do. `resetTimeout` is exposed here (Go took it from the underlying
  /// library's defaults) so callers — and tests — can tune the open→half-open delay.
  public func provideCircuitBreaker(
    logger: any Logger = NoopLogger(),
    metrics: any MetricsProvider = NoopMetricsProvider(),
    tags: [String: String] = [:],
    resetTimeout: Duration = StandardCircuitBreaker<ContinuousClock>.defaultResetTimeout
  ) -> any CircuitBreaker {
    let cfg = ensuringDefaults()

    do {
      try cfg.validate()
    } catch {
      logger.error("invalid circuit breaker config, providing noop circuit breaker", error)
      return NoopCircuitBreaker()
    }

    return StandardCircuitBreaker(
      name: cfg.name,
      errorRatePercentage: cfg.errorRate,
      minimumSampleThreshold: cfg.minimumSampleThreshold,
      resetTimeout: resetTimeout,
      logger: logger,
      metrics: metrics,
      tags: tags)
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case errorRate = "circuitBreakerErrorPercentage"
    case minimumSampleThreshold = "circuitBreakerMinimumOccurrenceThreshold"
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // Missing fields decode to Go's zero values so ``ensureDefaults()`` can fill them, matching how a
    // partial JSON object unmarshals into a Go struct.
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    errorRate = try c.decodeIfPresent(Double.self, forKey: .errorRate) ?? 0
    minimumSampleThreshold =
      try c.decodeIfPresent(UInt64.self, forKey: .minimumSampleThreshold) ?? 0
  }
}

/// A rejected ``CircuitBreakerConfig``. Go returned an aggregate `ozzo-validation` error; the port names
/// the two concrete failure modes so a caller can branch on them.
public enum CircuitBreakerConfigError: Error, Equatable {
  /// The name was empty (before defaulting).
  case missingName
  /// The error-rate percentage fell outside 0…100.
  case errorRateOutOfRange(Double)
}
