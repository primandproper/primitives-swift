import Foundation

/// Configures the feature flag manager, ported from platform-go's `featureflagscfg.Config`
/// (`featureflags/config/config.go`), including its `ValidateWithContext` and `ProvideFeatureFlagManager`.
///
/// Go's struct also carries a top-level `CircuitBreaker circuitbreakingcfg.Config` field, dropped here for
/// the same reason as ``LaunchDarklyConfig``/``PostHogConfig``: it only fed the circuit breaker handed to
/// a real vendor backend, and this platform never builds one (see ``makeFeatureFlagManager()``).
/// `Codable` ignoring unrecognized keys means a Go-authored payload's `circuitBreakerConfig` object still
/// decodes fine without a matching field.
///
/// ``provider`` stays a raw `String` rather than a ``FeatureFlagProvider``, the same move
/// ``Encoding``'s `EncodingConfig` makes for its content type: Go treats `""` (unset) as a valid,
/// meaningful value (falls through to noop) distinct from an *invalid* value, and ``validate()`` and
/// ``makeFeatureFlagManager()`` apply two different degrees of leniency to it, matching Go exactly.
public struct FeatureFlagsConfig: Codable, Sendable, Equatable {
  /// LaunchDarkly-specific settings. Required (non-`nil`) only when ``provider`` is `"launchdarkly"`.
  public var launchDarkly: LaunchDarklyConfig?
  /// PostHog-specific settings. Required (non-`nil`) only when ``provider`` is `"posthog"`.
  public var postHog: PostHogConfig?
  /// The selected backend as a raw string: `"launchdarkly"`, `"posthog"`, or `""` for the no-op manager.
  /// Resolved leniently (trimmed and lowercased) by ``makeFeatureFlagManager()``, matching Go's
  /// `strings.TrimSpace(strings.ToLower(c.Provider))`.
  public var provider: String

  public init(
    launchDarkly: LaunchDarklyConfig? = nil, postHog: PostHogConfig? = nil, provider: String = ""
  ) {
    self.launchDarkly = launchDarkly
    self.postHog = postHog
    self.provider = provider
  }

  private enum CodingKeys: String, CodingKey {
    case launchDarkly
    case postHog = "posthog"
    case provider
  }

  /// Validates the config, ported from Go's `ValidateWithContext`.
  ///
  /// Unlike ``makeFeatureFlagManager()``, this check is **strict**: it compares ``provider`` verbatim
  /// against `""`, `"launchdarkly"`, and `"posthog"` with no trimming or case-folding, exactly like Go's
  /// `validation.In(ProviderLaunchDarkly, ProviderPostHog, "")`. A value that `makeFeatureFlagManager()`
  /// would still resolve leniently (e.g. `"  LaunchDarkly  "`) fails validation here, matching Go's
  /// behavior of running these as two independent checks rather than one.
  /// - Throws: ``FeatureFlagsError/invalidProvider(_:)`` for an unrecognized provider string, or
  ///   ``FeatureFlagsError/missingProviderConfig(_:)`` when the matching sub-config is absent.
  public func validate() throws {
    guard provider.isEmpty || FeatureFlagProvider(rawValue: provider) != nil else {
      throw FeatureFlagsError.invalidProvider(provider)
    }
    if provider == FeatureFlagProvider.launchDarkly.rawValue && launchDarkly == nil {
      throw FeatureFlagsError.missingProviderConfig(.launchDarkly)
    }
    if provider == FeatureFlagProvider.postHog.rawValue && postHog == nil {
      throw FeatureFlagsError.missingProviderConfig(.postHog)
    }
  }

  /// Builds the configured ``FeatureFlagManager``, ported from Go's `Config.ProvideFeatureFlagManager`.
  ///
  /// Go's factory also threaded a `Logger`, `TracerProvider`, `MetricsProvider`, `*http.Client`, and
  /// `CircuitBreaker` into the real backends it could construct. None of that is needed here: both
  /// recognized providers are vendor server SDKs with no iOS analogue (see ``FeatureFlagProvider``), so
  /// selecting either throws immediately rather than opening a client, matching the "salsa20 treatment"
  /// this port applies to other vendor-SDK seams (``Cryptography``'s `EncryptionProvider.salsa20`,
  /// ``Encoding``'s non-JSON content types).
  ///
  /// Like Go, this does **not** call ``validate()`` first: an empty or unrecognized provider string
  /// resolves to ``NoopFeatureFlagManager`` without error, matching the `default` case of Go's `switch`.
  /// - Throws: ``FeatureFlagsError/unsupportedProvider(_:)`` when ``provider`` names a recognized backend.
  public func makeFeatureFlagManager() throws -> any FeatureFlagManager {
    switch provider.trimmingCharacters(in: .whitespaces).lowercased() {
    case FeatureFlagProvider.launchDarkly.rawValue:
      throw FeatureFlagsError.unsupportedProvider(.launchDarkly)
    case FeatureFlagProvider.postHog.rawValue:
      throw FeatureFlagsError.unsupportedProvider(.postHog)
    default:
      return NoopFeatureFlagManager()
    }
  }
}
