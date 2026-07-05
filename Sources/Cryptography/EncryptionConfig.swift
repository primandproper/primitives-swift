import Foundation

/// The selectable encryption provider, ported from the `ProviderAES`/`ProviderSalsa20` string
/// constants in platform-go's `cryptography/encryption/config`.
///
/// Go models the provider as a bare `string` validated with `validation.In(ProviderAES,
/// ProviderSalsa20)`. Swift gets a closed, self-validating enum (the same move ``Filtering``'s
/// `SortDirection` makes): an unknown provider string simply fails to decode, so the separate Go
/// `ValidateWithContext` check is unnecessary here.
///
/// Both raw values Go accepts are kept so a config payload authored against the Go service still
/// decodes. `salsa20`, however, is **not implemented** on this platform — see ``makeEncryptorDecryptor``.
public enum EncryptionProvider: String, Codable, Sendable, CaseIterable {
  /// AES-256-GCM. Fully supported; see ``AESGCMEncryptorDecryptor``.
  case aes
  /// NaCl secretbox (XSalsa20-Poly1305). Recognized for config compatibility but **unsupported** on
  /// Apple platforms — CryptoKit has no XSalsa20/secretbox primitive. Selecting it throws
  /// ``EncryptionError/unsupportedProvider(_:)``.
  case salsa20
}

/// Configuration for the encryption provider, ported from platform-go's `config.Config`.
///
/// Go's struct carries an `env:"PROVIDER" json:"provider"` string; iOS apps don't read the
/// environment (per the port's settled conventions), so this is a plain `Codable` decoded from a
/// bundled config / `Info.plist`. The Go field's `json` tag (`provider`) is preserved so the wire shape
/// matches.
public struct EncryptionConfig: Codable, Sendable, Equatable {
  public var provider: EncryptionProvider

  public init(provider: EncryptionProvider) {
    self.provider = provider
  }

  private enum CodingKeys: String, CodingKey {
    case provider
  }
}

extension EncryptionConfig {
  /// Builds the configured ``EncryptorDecryptor``, ported from Go's `ProvideEncryptorDecryptor`.
  ///
  /// The Go factory also threaded a `TracerProvider` and `Logger` for observability spans; those are
  /// dropped here (the crypto primitives are kept free of an observability dependency — the thrown
  /// ``EncryptionError`` is what a caller traces at its own layer).
  ///
  /// - Parameter key: the 32-byte master key (Go's `encryption.MasterKey`).
  /// - Throws: ``EncryptionError/incorrectKeyLength`` for a bad key, or
  ///   ``EncryptionError/unsupportedProvider(_:)`` for a recognized-but-unavailable provider.
  public func makeEncryptorDecryptor(key: Data) throws -> EncryptorDecryptor {
    switch provider {
    case .aes:
      return try AESGCMEncryptorDecryptor(key: key)
    case .salsa20:
      throw EncryptionError.unsupportedProvider(.salsa20)
    }
  }
}
