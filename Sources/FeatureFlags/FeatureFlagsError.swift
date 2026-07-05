import Foundation

/// Errors thrown while validating or building a ``FeatureFlagManager`` from ``FeatureFlagsConfig``.
///
/// Go spreads the equivalent failures across two independent checks: `ozzo-validation` rejects an
/// unrecognized `Provider` string or a missing provider-specific sub-config in `ValidateWithContext`,
/// while `ProvideFeatureFlagManager` normalizes the provider string and, for a recognized-but-unavailable
/// vendor backend, would have failed inside `launchdarkly.NewFeatureFlagManager`/
/// `posthog.NewFeatureFlagManager`. This port makes the "recognized but unavailable" case an explicit,
/// typed failure instead: see ``FeatureFlagProvider``.
public enum FeatureFlagsError: Error, Equatable, Sendable {
  /// ``FeatureFlagsConfig/provider`` was neither empty nor one of ``FeatureFlagProvider``'s raw values.
  /// Thrown by ``FeatureFlagsConfig/validate()``.
  case invalidProvider(String)

  /// ``FeatureFlagsConfig/provider`` named a provider whose matching sub-config
  /// (``FeatureFlagsConfig/launchDarkly`` or ``FeatureFlagsConfig/postHog``) was `nil`. Thrown by
  /// ``FeatureFlagsConfig/validate()``.
  case missingProviderConfig(FeatureFlagProvider)

  /// The provider is recognized but has no implementation on this platform (see ``FeatureFlagProvider``).
  /// Thrown by ``FeatureFlagsConfig/makeFeatureFlagManager()``.
  case unsupportedProvider(FeatureFlagProvider)
}

extension FeatureFlagsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidProvider(let provider):
      return "invalid feature flag provider: \(provider)"
    case .missingProviderConfig(let provider):
      return "missing configuration for feature flag provider: \(provider.rawValue)"
    case .unsupportedProvider(let provider):
      return "unsupported feature flag provider: \(provider.rawValue)"
    }
  }
}
