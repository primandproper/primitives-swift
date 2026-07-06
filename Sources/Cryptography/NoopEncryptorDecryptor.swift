import Foundation

/// A no-op ``EncryptorDecryptor``: encrypt and decrypt are the identity, returning `content` unchanged.
///
/// The safe default when encryption is disabled (or an unrecognized provider is configured), so call
/// sites don't have to nil-check an encryptor that may not exist — mirroring the Noop-conformer
/// convention the other seams follow (``Analytics``'s `NoopEventReporter`, `NoopPurchaseManager`).
///
/// - Warning: this performs **no encryption**. `encrypt` returns its input verbatim and the "ciphertext"
///   is plainly readable. Use it only where confidentiality is deliberately not required (tests, a
///   feature-flag-off path); never as a stand-in for real protection.
public struct NoopEncryptorDecryptor: EncryptorDecryptor {
  public init() {}

  /// Returns `content` unchanged.
  public func encrypt(_ content: String) -> String { content }

  /// Returns `content` unchanged, so `decrypt(encrypt(x)) == x` still holds.
  public func decrypt(_ content: String) -> String { content }
}
