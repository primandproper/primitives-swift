import Foundation
import Testing

@testable import Cryptography

@Suite("AES-256-GCM encryptor/decryptor")
struct AESGCMTests {
  /// A 32-byte key (matches the `testKey` literal in the Go `config_test.go`).
  private let key = Data("blahblahblahblahblahblahblahblah".utf8)

  private func newEncryptor() throws -> AESGCMEncryptorDecryptor {
    try AESGCMEncryptorDecryptor(key: key)
  }

  @Test("round-trips plaintext, and re-encryption differs (fresh nonce per call)")
  func roundTrip() throws {
    let ed = try newEncryptor()
    let plaintext = "AESGCMTests/roundTrip"

    let encrypted = try ed.encrypt(plaintext)
    #expect(!encrypted.isEmpty)
    // Guards against an identity "encryptor".
    #expect(encrypted != plaintext)

    let encrypted2 = try ed.encrypt(plaintext)
    // AES-GCM uses a fresh random nonce per call, so the same plaintext encrypts differently.
    #expect(encrypted != encrypted2)

    #expect(try ed.decrypt(encrypted) == plaintext)
    #expect(try ed.decrypt(encrypted2) == plaintext)
  }

  @Test("round-trips Unicode payloads")
  func unicodeRoundTrip() throws {
    let ed = try newEncryptor()
    let plaintext = "héllo • 世界 • 🔐"
    #expect(try ed.decrypt(ed.encrypt(plaintext)) == plaintext)
  }

  @Test("round-trips the empty string")
  func emptyRoundTrip() throws {
    let ed = try newEncryptor()
    #expect(try ed.decrypt(ed.encrypt("")) == "")
  }

  @Test("rejects a key that is not 32 bytes")
  func badKeyLength() {
    #expect(throws: EncryptionError.incorrectKeyLength) {
      _ = try AESGCMEncryptorDecryptor(key: Data("too short".utf8))
    }
    #expect(throws: EncryptionError.incorrectKeyLength) {
      _ = try AESGCMEncryptorDecryptor(key: Data(repeating: 0, count: 31))
    }
    #expect(throws: EncryptionError.incorrectKeyLength) {
      _ = try AESGCMEncryptorDecryptor(key: Data(repeating: 0, count: 33))
    }
  }

  @Test("decrypt rejects tampered ciphertext (GCM tag check)")
  func tamperDetection() throws {
    let ed = try newEncryptor()
    let encrypted = try ed.encrypt("sensitive payload")

    var raw = try #require(Base64URL.decode(encrypted))
    // Flip a bit in the authenticated body (past the nonce).
    raw[raw.count - 1] ^= 0x01
    let tampered = Base64URL.encode(raw)

    #expect(throws: EncryptionError.authenticationFailed) {
      _ = try ed.decrypt(tampered)
    }
  }

  @Test("decrypt rejects a ciphertext sealed under a different key")
  func wrongKey() throws {
    let ed = try newEncryptor()
    let encrypted = try ed.encrypt("secret")

    let otherKey = Data("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX".utf8)
    let otherEd = try AESGCMEncryptorDecryptor(key: otherKey)

    #expect(throws: EncryptionError.authenticationFailed) {
      _ = try otherEd.decrypt(encrypted)
    }
  }

  @Test("decrypt rejects invalid base64")
  func invalidBase64() throws {
    let ed = try newEncryptor()
    #expect(throws: EncryptionError.invalidCiphertextEncoding) {
      _ = try ed.decrypt("!!!not-base64!!!")
    }
  }

  @Test("decrypt rejects ciphertext too short for a nonce")
  func tooShortForNonce() throws {
    let ed = try newEncryptor()
    // Valid base64 that decodes to fewer than the 12-byte GCM nonce.
    let tooShort = Base64URL.encode(Data([0, 1, 2]))
    #expect(throws: EncryptionError.malformedCiphertext) {
      _ = try ed.decrypt(tooShort)
    }
  }
}
