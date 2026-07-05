/// Configuration for the PostHog backend, ported from platform-go's `posthog.Config`
/// (`featureflags/posthog/config.go`).
///
/// Go's struct also carries a `CircuitBreakerConfig circuitbreakingcfg.Config` field, dropped here for the
/// same reason as ``LaunchDarklyConfig``: it is only consumed when wiring a real client, which this
/// platform never does (see ``FeatureFlagsConfig/makeFeatureFlagManager()``), and `Codable` ignores
/// unrecognized JSON keys, so a Go-authored payload's `circuitBreakerConfig` object decodes fine without it.
public struct PostHogConfig: Codable, Sendable, Equatable {
  /// The PostHog project API key.
  public var projectAPIKey: String
  /// The PostHog personal API key, used for local flag evaluation in the Go SDK.
  public var personalAPIKey: String
  /// The PostHog host. Empty selects PostHog US Cloud (the SDK default); set it for EU Cloud
  /// (`https://eu.posthog.com`) or a self-hosted instance.
  public var endpoint: String

  public init(projectAPIKey: String = "", personalAPIKey: String = "", endpoint: String = "") {
    self.projectAPIKey = projectAPIKey
    self.personalAPIKey = personalAPIKey
    self.endpoint = endpoint
  }
}
