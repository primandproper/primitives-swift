import Foundation
import Testing

@testable import Cryptography

/// Cross-language interop (REPO-07): a real AES-256-GCM ciphertext minted by platform-go, pinned as a
/// literal, that Swift's ``AESGCMEncryptorDecryptor`` must decrypt back to the original plaintext.
///
/// This exercises the byte-level compatibility claim in ``AESGCMEncryptorDecryptor``'s doc — that Go's
/// `gcm.Seal(nonce, nonce, …)` layout (`nonce ‖ ciphertext ‖ tag`, URL-safe base64) is identical to
/// CryptoKit's `SealedBox.combined`. Because the nonce is captured *inside* the fixture, decryption is
/// fully deterministic (unlike the round-trip tests, which mint a fresh random nonce each call).
///
/// ## How the fixture was produced (reproducible)
///
/// Toolchain `go1.26.4 darwin/arm64`, standard library only (`crypto/aes` + `crypto/cipher`) — the
/// exact calls platform-go's `cryptography/encryption/aes/encrypt.go` makes:
///
/// ```go
/// key := []byte("blahblahblahblahblahblahblahblah") // 32 bytes, AES-256
/// block, _ := aes.NewCipher(key)
/// gcm, _ := cipher.NewGCM(block)
/// nonce := make([]byte, gcm.NonceSize())            // 12 bytes
/// io.ReadFull(rand.Reader, nonce)
/// sealed := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
/// fmt.Println(base64.URLEncoding.EncodeToString(sealed))
/// ```
@Suite("AES-256-GCM Go→Swift interop (REPO-07)")
struct AESGCMInteropTests {
  /// The 32-byte AES-256 key, as UTF-8 (matches the Go program and the round-trip suite's `testKey`).
  private let key = Data("blahblahblahblahblahblahblahblah".utf8)

  /// The plaintext the Go side encrypted (includes multi-byte UTF-8 to prove encoding fidelity).
  private let plaintext = "platform-swift REPO-07 AES-GCM interop fixture · 世界 🔐"

  /// The URL-safe base64 ciphertext Go emitted (`nonce ‖ ciphertext ‖ tag`). 89 raw bytes:
  /// 12 nonce + 61 ciphertext (the UTF-8 plaintext length) + 16 GCM tag.
  private let goCiphertext =
    "JO_UbDrZxieU0dGk2A4oPqBNy84C1z1zzmglkEnWrOOFwLhURvKkEZYvm9p3hAfQ1EQC81pLWoO_NGryMziG-Zt5Ts_c85iR0J_KH5Z5bjDpfSOBc7wuQBA="

  @Test("decrypts a ciphertext sealed by Go's crypto/cipher GCM")
  func decryptsGoCiphertext() throws {
    let ed = try AESGCMEncryptorDecryptor(key: key)
    #expect(try ed.decrypt(goCiphertext) == plaintext)
  }

  @Test("the pinned ciphertext is the Go nonce‖ct‖tag layout (12 + n + 16 bytes)")
  func layoutMatchesGo() throws {
    let raw = try #require(Base64URL.decode(goCiphertext))
    // 12-byte nonce, 16-byte tag, and the ciphertext body equal to the UTF-8 plaintext length.
    #expect(raw.count == 12 + plaintext.utf8.count + 16)
    #expect(raw.count == 89)
  }

  @Test("a wrong key fails authentication on the Go ciphertext (tag is bound to the key)")
  func wrongKeyRejectsGoCiphertext() throws {
    let otherEd = try AESGCMEncryptorDecryptor(key: Data("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX".utf8))
    #expect(throws: EncryptionError.authenticationFailed) {
      _ = try otherEd.decrypt(goCiphertext)
    }
  }
}
