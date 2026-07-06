import CircuitBreaking
import Foundation

/// Configuration for the PostHog backend, ported from platform-go's `posthog.Config`
/// (`featureflags/posthog/config.go`).
///
/// Go's struct carries a `CircuitBreakerConfig circuitbreakingcfg.Config` field
/// (`json:"circuitBreakerConfig"`). Earlier iterations of this port dropped it, because the seam threw
/// before any client was built; now that ``PostHogFeatureFlagManager`` is a real native backend, the
/// field is re-added and threaded into the manager (see ``FeatureFlagsConfig/makeFeatureFlagManager()``),
/// so a Go-authored payload's `circuitBreakerConfig` object round-trips *and* actually configures the
/// breaker guarding the decide calls. Reuses ``CircuitBreaking``'s ``CircuitBreakerConfig`` rather than
/// redefining its `circuitBreakerErrorPercentage`/`circuitBreakerMinimumOccurrenceThreshold` JSON keys,
/// exactly as ``Analytics``'s `SourceConfig` does.
public struct PostHogConfig: Codable, Sendable, Equatable {
  /// The PostHog project API key. Sent as the decide endpoint's `api_key` (a *public* project key, not
  /// the personal key), so it is the one credential ``PostHogFeatureFlagManager`` actually needs.
  public var projectAPIKey: String
  /// The PostHog personal API key, used for *local* flag evaluation in the Go SDK. The native manager
  /// evaluates flags *remotely* via the decide endpoint and never needs it, but it is kept for wire
  /// fidelity with a Go-authored config.
  public var personalAPIKey: String
  /// The PostHog host. Empty selects PostHog US Cloud
  /// (``PostHogFeatureFlagManager/defaultEndpoint``); set it for EU Cloud (`https://eu.i.posthog.com`)
  /// or a self-hosted instance.
  public var endpoint: String
  /// Circuit-breaker settings for the decide calls. Mirrors Go's `CircuitBreakerConfig` field
  /// (`json:"circuitBreakerConfig"`); threaded into the manager built by
  /// ``FeatureFlagsConfig/makeFeatureFlagManager()``.
  public var circuitBreaker: CircuitBreakerConfig

  public init(
    projectAPIKey: String = "",
    personalAPIKey: String = "",
    endpoint: String = "",
    circuitBreaker: CircuitBreakerConfig = CircuitBreakerConfig()
  ) {
    self.projectAPIKey = projectAPIKey
    self.personalAPIKey = personalAPIKey
    self.endpoint = endpoint
    self.circuitBreaker = circuitBreaker
  }

  private enum CodingKeys: String, CodingKey {
    case projectAPIKey
    case personalAPIKey
    case endpoint
    case circuitBreaker = "circuitBreakerConfig"
  }

  /// A missing key decodes to Go's zero value rather than failing, matching how a partial JSON object
  /// unmarshals into a Go struct (and letting `{}` decode).
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    projectAPIKey = try c.decodeIfPresent(String.self, forKey: .projectAPIKey) ?? ""
    personalAPIKey = try c.decodeIfPresent(String.self, forKey: .personalAPIKey) ?? ""
    endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    circuitBreaker =
      try c.decodeIfPresent(CircuitBreakerConfig.self, forKey: .circuitBreaker)
      ?? CircuitBreakerConfig()
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(projectAPIKey, forKey: .projectAPIKey)
    try c.encode(personalAPIKey, forKey: .personalAPIKey)
    try c.encode(endpoint, forKey: .endpoint)
    try c.encode(circuitBreaker, forKey: .circuitBreaker)
  }
}
