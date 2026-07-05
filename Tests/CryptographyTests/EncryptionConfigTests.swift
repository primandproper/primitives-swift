import Foundation
import Testing

@testable import Cryptography

@Suite("EncryptionConfig / provider factory")
struct EncryptionConfigTests {
  private let key = Data("blahblahblahblahblahblahblahblah".utf8)

  @Test("provider raw values mirror the Go constants")
  func rawValues() {
    #expect(EncryptionProvider.aes.rawValue == "aes")
    #expect(EncryptionProvider.salsa20.rawValue == "salsa20")
  }

  @Test("aes provider builds a working encryptor/decryptor")
  func aesProvider() throws {
    let config = EncryptionConfig(provider: .aes)
    let ed = try config.makeEncryptorDecryptor(key: key)
    #expect(try ed.decrypt(ed.encrypt("hello")) == "hello")
  }

  @Test("salsa20 provider is recognized but unsupported on this platform")
  func salsa20Unsupported() {
    let config = EncryptionConfig(provider: .salsa20)
    #expect(throws: EncryptionError.unsupportedProvider(.salsa20)) {
      _ = try config.makeEncryptorDecryptor(key: key)
    }
  }

  @Test("factory propagates a bad key length")
  func badKey() {
    let config = EncryptionConfig(provider: .aes)
    #expect(throws: EncryptionError.incorrectKeyLength) {
      _ = try config.makeEncryptorDecryptor(key: Data("short".utf8))
    }
  }

  @Test("Config decodes from Go's JSON shape (\"provider\" key)")
  func codableDecode() throws {
    let json = Data(#"{"provider":"aes"}"#.utf8)
    let config = try JSONDecoder().decode(EncryptionConfig.self, from: json)
    #expect(config.provider == .aes)
  }

  @Test("Config round-trips through JSON")
  func codableRoundTrip() throws {
    let original = EncryptionConfig(provider: .salsa20)
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(EncryptionConfig.self, from: encoded)
    #expect(decoded == original)
  }

  @Test("an unknown provider string fails to decode (self-validating enum)")
  func unknownProviderFailsDecode() {
    let json = Data(#"{"provider":"rot13"}"#.utf8)
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(EncryptionConfig.self, from: json)
    }
  }
}

@Suite("EncryptionError messages")
struct EncryptionErrorTests {
  @Test("messages match the Go sentinel error strings")
  func messages() {
    #expect(EncryptionError.incorrectKeyLength.errorDescription == "secret is not the right length")
    #expect(EncryptionError.malformedCiphertext.errorDescription == "malformed ciphertext")
    #expect(
      EncryptionError.authenticationFailed.errorDescription == "ciphertext authentication failed")
  }
}
