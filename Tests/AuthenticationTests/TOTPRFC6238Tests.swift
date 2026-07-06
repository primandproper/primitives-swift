import Foundation
import Testing

@testable import Authentication

/// REPO-10: the complete RFC 6238 Appendix B table — all 18 vectors (6 timestamps × 3 hash functions),
/// at the RFC's canonical **8-digit** truncation.
///
/// The RFC's Appendix B prints these codes directly, and they were independently reconfirmed against
/// `github.com/pquerna/otp` v1.5.0 (platform-go's TOTP dependency) via `totp.GenerateCodeCustom` with
/// `Digits: DigitsEight` and each RFC seed — so a match here proves the Swift RFC 4226 dynamic-
/// truncation math is correct for every algorithm *and* wire-compatible with the Go origin.
///
/// The seeds differ per algorithm (RFC 6238 §1.2): the SHA-1 seed is the 20-byte ASCII
/// "12345678901234567890", SHA-256 uses the 32-byte and SHA-512 the 64-byte extension of it. The base32
/// secrets below are those seeds under `base32.StdEncoding`.
@Suite("TOTP — RFC 6238 Appendix B, all 18 vectors at 8 digits")
struct TOTPRFC6238AllVectorsTests {
  private static let sha1Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  private static let sha256Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
  private static let sha512Secret =
    "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="

  @Test(
    "SHA-1 — 8 digits",
    arguments: [
      (59.0, "94287082"),
      (1_111_111_109.0, "07081804"),
      (1_111_111_111.0, "14050471"),
      (1_234_567_890.0, "89005924"),
      (2_000_000_000.0, "69279037"),
      (20_000_000_000.0, "65353130"),
    ])
  func sha1(unix: Double, expected: String) throws {
    let totp = TOTP(digits: 8, algorithm: .sha1)
    #expect(
      try totp.generate(secret: Self.sha1Secret, at: Date(timeIntervalSince1970: unix)) == expected)
  }

  @Test(
    "SHA-256 — 8 digits",
    arguments: [
      (59.0, "46119246"),
      (1_111_111_109.0, "68084774"),
      (1_111_111_111.0, "67062674"),
      (1_234_567_890.0, "91819424"),
      (2_000_000_000.0, "90698825"),
      (20_000_000_000.0, "77737706"),
    ])
  func sha256(unix: Double, expected: String) throws {
    let totp = TOTP(digits: 8, algorithm: .sha256)
    #expect(
      try totp.generate(secret: Self.sha256Secret, at: Date(timeIntervalSince1970: unix))
        == expected)
  }

  @Test(
    "SHA-512 — 8 digits",
    arguments: [
      (59.0, "90693936"),
      (1_111_111_109.0, "25091201"),
      (1_111_111_111.0, "99943326"),
      (1_234_567_890.0, "93441116"),
      (2_000_000_000.0, "38618901"),
      (20_000_000_000.0, "47863826"),
    ])
  func sha512(unix: Double, expected: String) throws {
    let totp = TOTP(digits: 8, algorithm: .sha512)
    #expect(
      try totp.generate(secret: Self.sha512Secret, at: Date(timeIntervalSince1970: unix))
        == expected)
  }
}
