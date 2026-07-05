import Foundation

/// Encrypts a plaintext string into an encoded ciphertext string, ported from platform-go's
/// `cryptography/encryption.Encryptor`.
///
/// Go's signature is `Encrypt(ctx context.Context, content string) (string, error)`. Two Go-isms drop
/// away in the Swift port:
///   * the `context.Context` parameter — cancellation/deadline plumbing that has no place in a pure
///     in-memory crypto primitive (the Go implementations only used it for observability spans);
///   * the `(value, error)` return — replaced by Swift's idiomatic `throws`.
public protocol Encryptor: Sendable {
  /// Encrypts `content` and returns the URL-safe base64 encoding of the sealed message.
  /// - Throws: ``EncryptionError`` on failure.
  func encrypt(_ content: String) throws -> String
}

/// Decrypts an encoded ciphertext string back into plaintext, ported from platform-go's
/// `cryptography/encryption.Decryptor`. See ``Encryptor`` for why `context.Context` and the Go error
/// return are dropped.
public protocol Decryptor: Sendable {
  /// Decrypts the URL-safe base64 `content` produced by ``Encryptor/encrypt(_:)``.
  /// - Throws: ``EncryptionError`` on malformed input or a failed authentication check.
  func decrypt(_ content: String) throws -> String
}

/// The composed encrypt+decrypt capability, ported from platform-go's
/// `cryptography/encryption.EncryptorDecryptor`.
public protocol EncryptorDecryptor: Encryptor, Decryptor {}
