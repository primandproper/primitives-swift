import Foundation
import Testing

@testable import Cookies

/// Ports `cookies/config_test.go`. Each Go subtest maps to a `@Test` here; the happy path leads.
@Suite("CookieConfig.validate")
struct CookieConfigValidateTests {
  /// A config that satisfies every rule. Keys are non-empty but *not* base64 — validation checks
  /// presence only, mirroring Go (base64 validity is enforced when the manager is built).
  private func validConfig() -> CookieConfig {
    CookieConfig(
      cookieName: "platform_cookie",
      base64EncodedHashKey: "hash-key",
      base64EncodedBlockKey: "block-key",
      lifetime: .seconds(24 * 60 * 60)
    )
  }

  @Test("accepts a standard config")
  func standard() throws {
    try validConfig().validate()
  }

  @Test("rejects a lifetime below the 5-minute minimum")
  func lifetimeBelowMinimum() {
    var cfg = validConfig()
    cfg.lifetime = .seconds(60)
    #expect(throws: CookieError.self) { try cfg.validate() }
  }

  @Test("allows an unset (zero) lifetime")
  func zeroLifetimeAllowed() throws {
    var cfg = validConfig()
    cfg.lifetime = .zero
    try cfg.validate()
  }

  @Test("rejects a missing cookie name")
  func missingName() {
    var cfg = validConfig()
    cfg.cookieName = ""
    #expect(throws: CookieError.self) { try cfg.validate() }
  }

  @Test("rejects a missing hash key")
  func missingHashKey() {
    var cfg = validConfig()
    cfg.base64EncodedHashKey = ""
    #expect(throws: CookieError.self) { try cfg.validate() }
  }

  @Test("rejects a missing block key")
  func missingBlockKey() {
    var cfg = validConfig()
    cfg.base64EncodedBlockKey = ""
    #expect(throws: CookieError.self) { try cfg.validate() }
  }

  @Test("accepts an explicit SameSite policy")
  func explicitSameSite() throws {
    var cfg = validConfig()
    cfg.sameSite = "strict"
    try cfg.validate()
  }

  @Test("accepts SameSite case-insensitively")
  func sameSiteCaseInsensitive() throws {
    var cfg = validConfig()
    cfg.sameSite = "Strict"
    try cfg.validate()
    #expect(cfg.resolvedSameSite == .strict)
  }

  @Test("rejects an unsupported SameSite value")
  func unsupportedSameSite() {
    var cfg = validConfig()
    cfg.sameSite = "sideways"
    #expect(throws: CookieError.self) { try cfg.validate() }
  }

  @Test("rejects SameSite=none without secureOnly")
  func sameSiteNoneWithoutSecure() {
    var cfg = validConfig()
    cfg.sameSite = "none"
    cfg.secureOnly = false
    #expect(throws: CookieError.self) { try cfg.validate() }
  }

  @Test("accepts SameSite=none with secureOnly")
  func sameSiteNoneWithSecure() throws {
    var cfg = validConfig()
    cfg.sameSite = "none"
    cfg.secureOnly = true
    try cfg.validate()
    #expect(cfg.resolvedSameSite == .none)
  }

  @Test("resolves an empty SameSite to lax, matching Go's sameSiteMode default")
  func emptyResolvesToLax() {
    #expect(validConfig().resolvedSameSite == .lax)
  }
}

@Suite("CookieConfig Codable")
struct CookieConfigCodableTests {
  @Test("lifetime encodes as integer nanoseconds, matching Go's time.Duration JSON")
  func encodesNanoseconds() throws {
    let cfg = CookieConfig(
      cookieName: "c", base64EncodedHashKey: "h", base64EncodedBlockKey: "b",
      lifetime: .seconds(3600))

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["cookieName"] as? String == "c")
    #expect(json["lifetime"] as? Int == 3_600_000_000_000)  // 1h in ns
  }

  @Test("round-trips through JSON")
  func roundTrips() throws {
    let original = CookieConfig(
      domain: "example.com", cookieName: "session", base64EncodedHashKey: "h",
      base64EncodedBlockKey: "b", sameSite: "strict", lifetime: .seconds(1800), secureOnly: true)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CookieConfig.self, from: data)
    #expect(decoded == original)
  }

  @Test("decodes a Go wire-shape payload (nanosecond lifetime)")
  func decodesGoWireShape() throws {
    let json = Data(
      #"{"domain":"example.com","cookieName":"session","base64EncodedHashKey":"h","base64EncodedBlockKey":"b","sameSite":"lax","lifetime":1800000000000,"secureOnly":true}"#
        .utf8)
    let cfg = try JSONDecoder().decode(CookieConfig.self, from: json)

    #expect(cfg.domain == "example.com")
    #expect(cfg.lifetime == .seconds(1800))
    #expect(cfg.secureOnly)
  }

  @Test("missing fields decode to Go zero values")
  func partialDecode() throws {
    let cfg = try JSONDecoder().decode(CookieConfig.self, from: Data("{}".utf8))
    #expect(cfg.cookieName == "")
    #expect(cfg.lifetime == .zero)
    #expect(cfg.secureOnly == false)
  }
}
