import Foundation
import Observability

/// Configures secret source selection, ported from platform-go's `secretscfg.Config`
/// (`secrets/config/config.go`), including its `ValidateWithContext`-adjacent provider gate and
/// `ProvideSecretSource` factory.
///
/// **Dropped from Go**: the `"gcp"` (`secrets/gcp`), `"ssm"` (`secrets/ssm`), and `"kubectl"`
/// (`secrets/kubectl`) provider backends — GCP Secret Manager, AWS SSM Parameter Store, and Kubernetes
/// Secrets are all server/cloud SDKs with no iOS analogue worth vendoring, and this port's dependency
/// list for `Secrets` is `Observability` only (no `HTTPClient`, so no thin REST reimplementation of any
/// of the three either, unlike e.g. ``FeatureFlags``' PostHog backend). The provider *strings* stay
/// recognized here — ``ProviderGCP``/``ProviderSSM``/``ProviderKubectl`` decode fine, matching Go's
/// `validation.In(...)` accepting them — but ``makeSecretSource(pillars:)`` throws
/// ``SecretsError/unsupportedProvider(_:)`` for any of the three, the same "recognized but
/// unimplemented" seam ``FeatureFlagsConfig`` uses for LaunchDarkly. A future vendor adapter (built
/// against `HTTPClient`, wrapping each service's REST API) can fill these in without a wire-format
/// change.
///
/// **Deliberate deviation from Go's default.** Go's `ProvideSecretSource` resolves a `nil` config or an
/// empty ``provider`` to `env.NewEnvSecretSource` — the simplest backend that works anywhere Go runs.
/// This port instead defaults to ``ProviderKeychain``: on iOS, the Keychain is the durable, native
/// secret store, while ``EnvironmentSecretSource`` is explicitly the debug/simulator convenience (see
/// that type's doc). Defaulting to Keychain keeps an unconfigured/empty ``provider`` resolving to the
/// safe-for-production backend rather than one that silently no-ops outside a debug build.
public struct SecretsConfig: Codable, Sendable, Equatable {
  /// Selects ``KeychainSecretSource``. Also what an empty ``provider`` resolves to.
  public static let providerKeychain = "keychain"
  /// Selects ``EnvironmentSecretSource``.
  public static let providerEnvironment = "environment"
  /// Selects ``NoopSecretSource``.
  public static let providerNoop = "noop"
  /// Recognized for wire compatibility with a Go-authored config; unimplemented on this platform. See
  /// this type's doc.
  public static let providerGCP = "gcp"
  /// Recognized for wire compatibility with a Go-authored config; unimplemented on this platform. See
  /// this type's doc.
  public static let providerSSM = "ssm"
  /// Recognized for wire compatibility with a Go-authored config; unimplemented on this platform. See
  /// this type's doc.
  public static let providerKubectl = "kubectl"

  /// Settings for ``KeychainSecretSource``. Ported concept only — Go's `env.Config{}` (the sub-config
  /// its equivalent provider carries) has no fields at all, since environment variables need no
  /// per-instance configuration; the Keychain backend needs at least a service name to scope its items
  /// under, so this is new to the port rather than translated from a Go type.
  public struct KeychainConfig: Codable, Sendable, Equatable {
    /// The `kSecAttrService` every item is scoped under. Empty resolves to the app's bundle identifier
    /// at `makeSecretSource(pillars:)` time — see that method.
    public var service: String
    /// Optional `kSecAttrAccessGroup`, for sharing secrets across an app group's targets/extensions.
    public var accessGroup: String?

    public init(service: String = "", accessGroup: String? = nil) {
      self.service = service
      self.accessGroup = accessGroup
    }

    private enum CodingKeys: String, CodingKey {
      case service
      case accessGroup
    }

    public init(from decoder: any Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      service = try c.decodeIfPresent(String.self, forKey: .service) ?? ""
      accessGroup = try c.decodeIfPresent(String.self, forKey: .accessGroup)
    }
  }

  /// The selected backend as a raw string: ``providerKeychain``, ``providerEnvironment``,
  /// ``providerNoop``, one of the recognized-but-unsupported cloud provider strings, or `""` for the
  /// default (``providerKeychain`` — see this type's doc).
  public var provider: String
  /// Settings for ``KeychainSecretSource``, consulted when ``provider`` resolves to it.
  public var keychain: KeychainConfig

  public init(provider: String = "", keychain: KeychainConfig = KeychainConfig()) {
    self.provider = provider
    self.keychain = keychain
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case keychain
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    keychain = try c.decodeIfPresent(KeychainConfig.self, forKey: .keychain) ?? KeychainConfig()
  }

  /// Builds the configured ``SecretSource``, ported from Go's `Config.ProvideSecretSource`.
  ///
  /// `provider` is resolved leniently (trimmed and lowercased), matching Go's
  /// `strings.TrimSpace(strings.ToLower(cfg.Provider))`. Unlike Go, an empty/unrecognized string does
  /// **not** silently fall through to a working backend for the *unrecognized* case: only `""` resolves
  /// to the default (``providerKeychain``); any other unrecognized string throws
  /// ``SecretsError/unsupportedProvider(_:)``, matching Go's own `default` case
  /// (`unknown secret source provider: %q`).
  /// - Throws: ``SecretsError/unsupportedProvider(_:)`` for `"gcp"`/`"ssm"`/`"kubectl"` or any other
  ///   unrecognized provider string.
  public func makeSecretSource(
    pillars: Pillars, bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "platform-swift"
  ) throws -> any SecretSource {
    switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "", Self.providerKeychain:
      let service = keychain.service.isEmpty ? bundleIdentifier : keychain.service
      return KeychainSecretSource(
        service: service, accessGroup: keychain.accessGroup, pillars: pillars)
    case Self.providerEnvironment:
      return EnvironmentSecretSource(pillars: pillars)
    case Self.providerNoop:
      return NoopSecretSource()
    case Self.providerGCP:
      throw SecretsError.unsupportedProvider(Self.providerGCP)
    case Self.providerSSM:
      throw SecretsError.unsupportedProvider(Self.providerSSM)
    case Self.providerKubectl:
      throw SecretsError.unsupportedProvider(Self.providerKubectl)
    default:
      throw SecretsError.unsupportedProvider(provider)
    }
  }
}
