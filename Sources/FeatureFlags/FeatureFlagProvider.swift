/// The selectable feature-flag backend, ported from the `Provider*` string constants in platform-go's
/// `featureflags/config` package (`ProviderLaunchDarkly`, `ProviderPostHog`).
///
/// Both raw values Go accepts are kept so a config payload authored against the Go service still
/// resolves. Neither is implemented on this platform: both are vendor server SDKs (LaunchDarkly's and
/// PostHog's Go SDKs, fronted by OpenFeature) with no iOS analogue worth vendoring, so selecting either
/// throws ``FeatureFlagsError/unsupportedProvider(_:)`` from
/// ``FeatureFlagsConfig/makeFeatureFlagManager()``. This is the same seam ``Cryptography``'s
/// `EncryptionProvider.salsa20` and ``Encoding``'s non-JSON `ContentType` cases use: the case stays
/// decodable, but the factory that would construct the real backend refuses to.
public enum FeatureFlagProvider: String, Codable, Sendable, CaseIterable {
  /// LaunchDarkly, via platform-go's OpenFeature-fronted `featureflags/launchdarkly` package.
  case launchDarkly = "launchdarkly"
  /// PostHog, via platform-go's OpenFeature-fronted `featureflags/posthog` package.
  case postHog = "posthog"
}
