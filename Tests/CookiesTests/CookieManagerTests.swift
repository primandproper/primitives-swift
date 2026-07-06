import Foundation
import Testing

@testable import Cookies

/// Ports `cookies/cookies_test.go`. The MAC/round-trip behavior is exercised against the reproduced
/// `securecookie` signing envelope; the deferred encryption path (see ``CookieManager``) is not tested
/// because it isn't ported.
private struct Example: Codable, Equatable {
  var name: String
}

/// A 32-byte key, standard-base64-encoded — the analogue of the Go test's `testKey` fed through
/// `base64.StdEncoding`.
private let testKeyBase64 = Data("HEREISA32CHARSECRETWHICHISMADEUP".utf8).base64EncodedString()
/// A second, distinct 32-byte key, for the "signed under a different key" MAC test.
private let otherKeyBase64 = Data("ADIFFERENT32CHARSECRETVALUE12345".utf8).base64EncodedString()

private func validConfig() -> CookieConfig {
  CookieConfig(
    cookieName: "platform_cookie",
    base64EncodedHashKey: testKeyBase64,
    base64EncodedBlockKey: testKeyBase64
  )
}

@Suite("CookieManager construction")
struct CookieManagerConstructionTests {
  @Test("builds from a valid config")
  func standard() throws {
    _ = try CookieManager(config: validConfig())
  }

  @Test("rejects an invalid config (SameSite=none without secureOnly)")
  func rejectsInvalidConfig() {
    var cfg = validConfig()
    cfg.sameSite = "none"
    cfg.secureOnly = false
    #expect(throws: CookieError.self) { try CookieManager(config: cfg) }
  }

  @Test("rejects an invalid hash key without echoing the key material")
  func invalidHashKey() {
    var cfg = validConfig()
    cfg.base64EncodedHashKey = "not-valid-base64!!!"
    do {
      _ = try CookieManager(config: cfg)
      Issue.record("expected construction to throw")
    } catch {
      #expect(error == .invalidHashKey)
      // The error text must never leak the (secret) key material.
      #expect(!error.localizedDescription.contains(cfg.base64EncodedHashKey))
    }
  }

  @Test("rejects an invalid block key without echoing the key material")
  func invalidBlockKey() {
    var cfg = validConfig()
    cfg.base64EncodedBlockKey = "not-valid-base64!!!"
    do {
      _ = try CookieManager(config: cfg)
      Issue.record("expected construction to throw")
    } catch {
      #expect(error == .invalidBlockKey)
      #expect(!error.localizedDescription.contains(cfg.base64EncodedBlockKey))
    }
  }
}

@Suite("CookieManager encode/decode")
struct CookieManagerEncodeDecodeTests {
  @Test("encodes a non-empty value and round-trips it back")
  func roundTrip() throws {
    let m = try CookieManager(config: validConfig())

    let encoded = try m.encode(name: "session", Example(name: "roundTrip"))
    #expect(!encoded.isEmpty)

    let decoded = try m.decode(name: "session", from: encoded, as: Example.self)
    #expect(decoded == Example(name: "roundTrip"))
  }

  @Test("rejects a value verified under a different cookie name (name is bound into the MAC)")
  func wrongName() throws {
    let m = try CookieManager(config: validConfig())
    let encoded = try m.encode(name: "session", Example(name: "x"))

    #expect(throws: CookieError.macInvalid) {
      _ = try m.decode(name: "other", from: encoded, as: Example.self)
    }
  }

  @Test("rejects a value signed with a different hash key")
  func wrongKey() throws {
    let signer = try CookieManager(config: validConfig())
    let encoded = try signer.encode(name: "session", Example(name: "x"))

    var otherCfg = validConfig()
    otherCfg.base64EncodedHashKey = otherKeyBase64
    let verifier = try CookieManager(config: otherCfg)

    #expect(throws: CookieError.macInvalid) {
      _ = try verifier.decode(name: "session", from: encoded, as: Example.self)
    }
  }

  @Test("rejects a structurally malformed value")
  func malformed() throws {
    let m = try CookieManager(config: validConfig())
    #expect(throws: CookieError.malformedValue) {
      _ = try m.decode(name: "session", from: "@@@not-base64@@@", as: Example.self)
    }
  }

  @Test("enforces the configured lifetime, rejecting an expired value")
  func expiry() throws {
    var cfg = validConfig()
    cfg.lifetime = .seconds(300)  // 5-minute bound

    let signer = try CookieManager(config: cfg, now: { 1000 })
    let encoded = try signer.encode(name: "session", Example(name: "x"))

    // Decode 400s later — past the 300s bound.
    let verifier = try CookieManager(config: cfg, now: { 1400 })
    #expect(throws: CookieError.expired) {
      _ = try verifier.decode(name: "session", from: encoded, as: Example.self)
    }
  }

  @Test("an unset lifetime falls back to securecookie's 30-day decode bound")
  func unsetLifetimeUsesDefaultBound() throws {
    let cfg = validConfig()  // lifetime .zero

    let signer = try CookieManager(config: cfg, now: { 1000 })
    let encoded = try signer.encode(name: "session", Example(name: "x"))

    // Just inside the 30-day window still verifies.
    let thirtyDays: Int64 = 86_400 * 30
    let withinWindow = try CookieManager(config: cfg, now: { 1000 + thirtyDays })
    let decoded = try withinWindow.decode(name: "session", from: encoded, as: Example.self)
    #expect(decoded == Example(name: "x"))

    // Past the 30-day default — Go's securecookie bounds an unset lifetime to 30 days
    // (securecookie.New sets maxAge = 86400*30; NewCookieManager only overrides it when
    // Lifetime > 0), so a captured cookie cannot be replayed indefinitely.
    let pastWindow = try CookieManager(config: cfg, now: { 1000 + thirtyDays + 1 })
    #expect(throws: CookieError.expired) {
      _ = try pastWindow.decode(name: "session", from: encoded, as: Example.self)
    }
  }
}

@Suite("CookieManager.buildCookie")
struct CookieManagerBuildCookieTests {
  @Test("applies the configured security attributes and round-trips the value")
  func appliesAttributes() throws {
    var cfg = validConfig()
    cfg.domain = "example.com"
    cfg.lifetime = .seconds(3600)
    cfg.secureOnly = true

    let m = try CookieManager(config: cfg)
    let cookie = try m.buildCookie(name: "session", Example(name: "attrs"))

    #expect(cookie.name == "session")
    #expect(!cookie.value.isEmpty)
    #expect(cookie.path == "/")
    #expect(cookie.domain == "example.com")
    #expect(cookie.isSecure)
    #expect(cookie.sameSitePolicy == .sameSiteLax)
    #expect(cookie.expiresDate != nil)

    // The embedded value must still round-trip through decode.
    let decoded = try m.decode(name: "session", from: cookie.value, as: Example.self)
    #expect(decoded == Example(name: "attrs"))
  }

  @Test("honors a configured Strict SameSite policy")
  func honorsSameSiteStrict() throws {
    var cfg = validConfig()
    cfg.domain = "example.com"
    cfg.sameSite = "strict"

    let m = try CookieManager(config: cfg)
    let cookie = try m.buildCookie(name: "session", Example(name: "x"))
    #expect(cookie.sameSitePolicy == .sameSiteStrict)
  }

  @Test("without a lifetime omits expiry and stays non-secure by default")
  func withoutLifetime() throws {
    var cfg = validConfig()
    cfg.domain = "example.com"  // required by HTTPCookie, unlike Go's http.Cookie

    let m = try CookieManager(config: cfg)
    let cookie = try m.buildCookie(name: "session", Example(name: "x"))

    #expect(cookie.expiresDate == nil)
    #expect(!cookie.isSecure)
    #expect(cookie.sameSitePolicy == .sameSiteLax)
  }

  @Test("requires a non-empty domain (HTTPCookie cannot be built without one)")
  func requiresDomain() throws {
    let m = try CookieManager(config: validConfig())  // empty domain
    #expect(throws: CookieError.missingDomain) {
      _ = try m.buildCookie(name: "session", Example(name: "x"))
    }
  }
}
