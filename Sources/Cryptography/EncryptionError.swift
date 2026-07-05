import Foundation

/// Errors thrown by ``EncryptorDecryptor`` implementations, ported from the package-level `var`
/// sentinels in platform-go's `cryptography/encryption/errors.go`.
///
/// Go exposes these as three sentinel `error` values compared with `errors.Is`. Swift folds them into
/// a single typed enum — the idiomatic shape for a closed set of failure modes — while preserving the
/// exact Go messages in ``errorDescription`` so any log/telemetry text lines up across the two ports.
/// `unsupportedProvider` and `invalidCiphertextEncoding` are new, finer-grained cases with no Go
/// sentinel (Go surfaced these as a formatted error and a base64 decode error respectively).
public enum EncryptionError: Error, Equatable, Sendable {
  /// The supplied key was not the required length (AES-256 needs exactly 32 bytes).
  /// Mirrors Go's `ErrIncorrectKeyLength` ("secret is not the right length").
  case incorrectKeyLength

  /// The ciphertext was too short to contain a nonce. Mirrors Go's `ErrMalformedCiphertext`.
  case malformedCiphertext

  /// The ciphertext failed its authentication check (tampering, wrong key, or truncation past the
  /// nonce). Mirrors Go's `ErrAuthenticationFailed`.
  case authenticationFailed

  /// The ciphertext string was not valid URL-safe base64. Go surfaced this as the underlying
  /// `base64.URLEncoding.DecodeString` error; the port names it explicitly.
  case invalidCiphertextEncoding

  /// The configured provider is recognized but not available on this platform (e.g. `salsa20`,
  /// which relies on NaCl secretbox and has no CryptoKit analogue). See ``EncryptionProvider``.
  case unsupportedProvider(EncryptionProvider)
}

extension EncryptionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .incorrectKeyLength:
      return "secret is not the right length"
    case .malformedCiphertext:
      return "malformed ciphertext"
    case .authenticationFailed:
      return "ciphertext authentication failed"
    case .invalidCiphertextEncoding:
      return "ciphertext is not valid url-safe base64"
    case .unsupportedProvider(let provider):
      return "unsupported encryption provider: \(provider.rawValue)"
    }
  }
}
