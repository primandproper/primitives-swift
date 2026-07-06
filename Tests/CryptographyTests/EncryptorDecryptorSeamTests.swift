import Foundation
import Testing

@testable import Cryptography

/// REPO-05: regression tests for the ``EncryptorDecryptor`` seam's Noop and Mock conformers.
@Suite("EncryptorDecryptor seam — Noop + Mock")
struct EncryptorDecryptorSeamTests {
  @Test("NoopEncryptorDecryptor is the identity and round-trips")
  func noopIsIdentity() {
    let noop = NoopEncryptorDecryptor()
    #expect(noop.encrypt("hello") == "hello")
    #expect(noop.decrypt("hello") == "hello")
    // The defining Noop property: decrypt∘encrypt is the identity.
    #expect(noop.decrypt(noop.encrypt("secret message")) == "secret message")
  }

  @Test("MockEncryptorDecryptor defaults to passthrough and records every call")
  func mockDefaultPassthroughRecords() throws {
    let mock = MockEncryptorDecryptor()
    #expect(try mock.encrypt("a") == "a")
    #expect(try mock.decrypt("b") == "b")
    #expect(mock.encryptCalls == ["a"])
    #expect(mock.decryptCalls == ["b"])
  }

  @Test("MockEncryptorDecryptor routes through its handlers")
  func mockHandlers() throws {
    let mock = MockEncryptorDecryptor(
      encryptHandler: { "enc(\($0))" },
      decryptHandler: {
        $0.replacingOccurrences(of: "enc(", with: "").replacingOccurrences(of: ")", with: "")
      })
    #expect(try mock.encrypt("x") == "enc(x)")
    #expect(try mock.decrypt("enc(x)") == "x")
  }

  @Test("MockEncryptorDecryptor propagates a thrown error")
  func mockThrows() {
    let mock = MockEncryptorDecryptor(
      encryptHandler: { _ in throw EncryptionError.malformedCiphertext })
    #expect(throws: EncryptionError.malformedCiphertext) {
      _ = try mock.encrypt("x")
    }
  }

  @Test("a Mock can stand in wherever an EncryptorDecryptor is required")
  func mockConformsToProtocol() throws {
    func roundTrip(_ ed: some EncryptorDecryptor, _ value: String) throws -> String {
      try ed.decrypt(ed.encrypt(value))
    }
    #expect(try roundTrip(MockEncryptorDecryptor(), "z") == "z")
    #expect(try roundTrip(NoopEncryptorDecryptor(), "z") == "z")
  }
}

/// REPO-11: the padded URL-safe base64 codec must reject the standard alphabet and mid-string padding
/// that Go's `base64.URLEncoding` rejects, rather than leniently translating them.
@Suite("Cryptography Base64URL — strict decode (REPO-11)")
struct Base64URLStrictDecodeTests {
  @Test("round-trips the URL-safe alphabet it emits")
  func roundTrips() throws {
    // 0xFB 0xFF encodes to "-_8=" (contains both '-' and '_').
    let data = Data([0xFB, 0xFF])
    let encoded = Base64URL.encode(data)
    #expect(encoded == "-_8=")
    #expect(Base64URL.decode(encoded) == data)
  }

  @Test("rejects the standard-alphabet + and / that Go's URLEncoding rejects")
  func rejectsStandardAlphabet() {
    // "+_8=" / "-/8=" carry a standard-alphabet char the URL decoder must not accept.
    #expect(Base64URL.decode("+_8=") == nil)
    #expect(Base64URL.decode("-/8=") == nil)
  }

  @Test("rejects padding sitting mid-string")
  func rejectsMidStringPadding() {
    #expect(Base64URL.decode("ab=cd") == nil)
    #expect(Base64URL.decode("YQ==YQ==") == nil)
  }

  @Test("rejects whitespace and other non-alphabet bytes")
  func rejectsGarbage() {
    #expect(Base64URL.decode("ab cd") == nil)
    #expect(Base64URL.decode("ab@cd") == nil)
  }
}

/// REPO-11: the strictness must be visible at the ``AESGCMEncryptorDecryptor`` boundary — a ciphertext
/// string carrying a standard-alphabet char is an encoding error, not a passthrough.
@Suite("AES-GCM decrypt rejects non-URL-safe base64 (REPO-11)")
struct AESGCMStrictEncodingTests {
  private let key = Data(repeating: 0x42, count: 32)

  @Test("a valid ciphertext round-trips after the SymmetricKey change")
  func roundTrips() throws {
    let ed = try AESGCMEncryptorDecryptor(key: key)
    #expect(try ed.decrypt(ed.encrypt("payload")) == "payload")
  }

  @Test("a ciphertext with a standard-alphabet '/' is rejected as an encoding error")
  func rejectsStandardAlphabetCiphertext() throws {
    let ed = try AESGCMEncryptorDecryptor(key: key)
    let valid = try ed.encrypt("payload")
    // Splice a '/' in — it is not part of the URL-safe alphabet, so decode must fail before AES.
    let tampered = "/" + valid.dropFirst()
    #expect(throws: EncryptionError.invalidCiphertextEncoding) {
      _ = try ed.decrypt(tampered)
    }
  }
}
