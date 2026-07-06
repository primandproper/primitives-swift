import Foundation

/// Errors surfaced by this module's ``SecretSource`` conformers and ``SecretsConfig``.
///
/// Go's `secrets` package exposes a single package-level sentinel, `ErrSecretNotFound`, that every
/// backend wraps with `errors.Wrap`/`op.Error` for context; callers unwrap it with `errors.Is`. This
/// port instead carries the failing secret's name directly on the case (the idiom this repo's other
/// typed errors use — see `LLMError.modelNotFound(_:)`), so a caught error is self-describing without a
/// separate `errors.Is` check.
public enum SecretsError: Error, Equatable, Sendable {
  /// No secret exists under this name. The direct analogue of Go's `secrets.ErrSecretNotFound`; see
  /// ``SecretSource`` for the not-found/empty distinction this preserves.
  ///
  /// ``KeychainSecretSource`` throws this when `SecItemCopyMatching` returns `errSecItemNotFound`.
  /// ``EnvironmentSecretSource`` throws this when the name is absent from both the process environment
  /// and the bundle's `Info.plist` (mirroring Go's `env.envSecretSource` erroring on `os.LookupEnv`'s
  /// `ok == false`).
  case notFound(String)

  /// The Keychain returned a matching item, but its stored value wasn't decodable as UTF-8 text.
  /// Go has no analogue (its backends only ever produce well-formed strings); this case exists purely
  /// as a safety net around a Keychain item written by something other than this module.
  case malformedSecretData(name: String)

  /// A Keychain operation failed with a status other than `errSecSuccess`/`errSecItemNotFound`. Carries
  /// the raw `OSStatus` (as `Int32`, to avoid requiring callers to import `Security`) for diagnostics.
  case keychainFailure(name: String, status: Int32)

  /// ``SecretsConfig/provider`` named a recognized-but-unsupported backend — the `"gcp"`, `"ssm"`, or
  /// `"kubectl"` provider strings Go's `secretscfg.Config` also accepts. Those are server/cloud SDKs
  /// this port deliberately does not vendor (see ``SecretsConfig`` for what was dropped); the string
  /// stays a recognized, decodable value so a Go-authored config round-trips, but selecting it throws
  /// here instead of reaching for a client this platform has no business holding.
  case unsupportedProvider(String)
}

extension SecretsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notFound(let name):
      return "secret not found: \(name)"
    case .malformedSecretData(let name):
      return "secret \(name) is not valid UTF-8 text"
    case .keychainFailure(let name, let status):
      return "keychain lookup for \(name) failed with status \(status)"
    case .unsupportedProvider(let provider):
      return "unsupported secrets provider: \(provider)"
    }
  }
}
