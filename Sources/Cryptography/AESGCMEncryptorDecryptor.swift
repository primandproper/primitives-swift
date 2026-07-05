import CryptoKit
import Foundation

/// An ``EncryptorDecryptor`` using AES-256-GCM, ported from platform-go's
/// `cryptography/encryption/aes`.
///
/// Go builds this from `crypto/aes` + `crypto/cipher.NewGCM`; the Swift port uses Apple **CryptoKit**
/// (`AES.GCM`), the clean equivalent. The wire format is preserved exactly so ciphertext round-trips
/// between the Go service and the iOS client:
///
///   * **Key**: exactly 32 bytes (AES-256). A wrong length throws ``EncryptionError/incorrectKeyLength``,
///     matching Go's `len(key) != 32` guard.
///   * **Nonce**: a fresh random 12-byte nonce per call — the GCM standard size Go uses via
///     `gcm.NonceSize()`, and CryptoKit's `AES.GCM.Nonce()` default. Because the nonce is random,
///     encrypting the same plaintext twice yields different ciphertexts.
///   * **Layout**: `nonce ‖ ciphertext ‖ tag`, then URL-safe base64. Go produces this with
///     `gcm.Seal(nonce, nonce, …)`; CryptoKit's `AES.GCM.SealedBox.combined` has the identical layout,
///     so the two are byte-compatible.
///
/// Authentication (GCM's tag) is verified on decrypt: any tampering — or a truncated body past the
/// nonce — throws ``EncryptionError/authenticationFailed``, exactly as Go's `gcm.Open` returns an error.
public struct AESGCMEncryptorDecryptor: EncryptorDecryptor {
  private let key: Data

  /// GCM standard nonce length, matching Go's `gcm.NonceSize()`.
  private static let nonceSize = 12

  /// Creates an encryptor/decryptor from a 32-byte key.
  /// - Throws: ``EncryptionError/incorrectKeyLength`` if `key` is not exactly 32 bytes.
  public init(key: Data) throws {
    guard key.count == 32 else {
      throw EncryptionError.incorrectKeyLength
    }
    self.key = key
  }

  /// Convenience initializer accepting the key as raw bytes.
  public init(key: [UInt8]) throws {
    try self.init(key: Data(key))
  }

  public func encrypt(_ content: String) throws -> String {
    let symmetricKey = SymmetricKey(data: key)
    let nonce = AES.GCM.Nonce()  // fresh random 12-byte nonce per call
    let sealed = try AES.GCM.seal(Data(content.utf8), using: symmetricKey, nonce: nonce)
    guard let combined = sealed.combined else {
      // Only nil for non-standard nonce sizes; unreachable with the default 12-byte nonce.
      throw EncryptionError.malformedCiphertext
    }
    return Base64URL.encode(combined)
  }

  public func decrypt(_ content: String) throws -> String {
    guard let raw = Base64URL.decode(content) else {
      throw EncryptionError.invalidCiphertextEncoding
    }

    // Matches Go's explicit "ciphertext too short for nonce" guard before attempting to open.
    guard raw.count >= Self.nonceSize else {
      throw EncryptionError.malformedCiphertext
    }

    let symmetricKey = SymmetricKey(data: key)
    do {
      let box = try AES.GCM.SealedBox(combined: raw)
      let plaintext = try AES.GCM.open(box, using: symmetricKey)
      return String(decoding: plaintext, as: UTF8.self)
    } catch {
      // A bad tag, wrong key, or a body too short to hold the 16-byte tag all land here — the same
      // outcomes Go collapses into a failed `gcm.Open`.
      throw EncryptionError.authenticationFailed
    }
  }
}
