import Foundation
import Testing

@testable import Cookies

/// Cross-language interop (REPO-07): a signed cookie value minted by Go's `gorilla/securecookie`,
/// pinned as a literal, that Swift's ``CookieManager`` must verify and decode.
///
/// This proves the byte-level claim in ``CookieManager``'s doc — that the reproduced HMAC-SHA256
/// envelope (`base64url( "date|" ‖ base64url(payload) ‖ "|" ‖ mac )`, with the cookie name bound into
/// the MAC over `name|date|payload`) is wire-compatible with a Go `securecookie` configured for a hash
/// key with **no block key and a JSON serializer**.
///
/// ### Why securecookie is configured to a subset here
///
/// platform-go's `cookies.Manager` wraps `securecookie.New(hashKey, blockKey)` with its *default gob
/// serializer* and a *non-nil block key* (AES-CTR encryption). The Swift port deliberately reproduces
/// only the signing envelope (JSON serializer, no encryption) — see ``CookieManager``'s "deferred /
/// honestly-incompatible pieces" note. The fixture therefore configures Go's securecookie to exactly
/// that supported subset; a value from the *default* Manager (gob + AES-CTR) is intentionally NOT
/// Swift-decodable and is out of scope for this port.
///
/// ## How the fixture was produced (reproducible)
///
/// Toolchain `go1.26.4 darwin/arm64`, `github.com/gorilla/securecookie v1.1.2`:
///
/// ```go
/// hashKey := []byte("HEREISA32CHARSECRETWHICHISMADEUP") // 32 bytes
/// sc := securecookie.New(hashKey, nil)                  // nil block key => no encryption
/// sc.SetSerializer(securecookie.JSONEncoder{})          // JSON, not the default gob
/// type payload struct{ Name string `json:"name"` }
/// encoded, _ := sc.Encode("platform_cookie", payload{Name: "REPO-07 interop"})
/// // securecookie stamps the value with time.Now().Unix(); the embedded timestamp was 1783317297.
/// ```
private struct Example: Codable, Equatable {
  var name: String
}

@Suite("securecookie Go→Swift interop (REPO-07)")
struct SecureCookieInteropTests {
  /// Hash key, standard-base64 (matches Go's `base64.StdEncoding` of the 32-byte key).
  private let hashKeyStdB64 = "SEVSRUlTQTMyQ0hBUlNFQ1JFVFdISUNISVNNQURFVVA="
  private let cookieName = "platform_cookie"
  /// The Go-emitted signed envelope, verbatim.
  private let goEncoded =
    "MTc4MzMxNzI5N3xleUp1WVcxbElqb2lVa1ZRVHkwd055QnBiblJsY205d0luMEt8iMLJezT2s8NU3LPnGI9WcKq4yzHSqI5zYtfaWzuzOTg="
  /// The Unix timestamp securecookie embedded when it minted the fixture.
  private let goTimestamp: Int64 = 1_783_317_297

  /// A config matching the Go side. Go used a nil block key, but ``CookieConfig`` requires a non-empty
  /// base64 block key (validated, never used by the ported signing path — see ``CookieManager``), so we
  /// reuse the hash key's bytes for it; it does not enter the HMAC.
  private func config() -> CookieConfig {
    CookieConfig(
      cookieName: cookieName,
      base64EncodedHashKey: hashKeyStdB64,
      base64EncodedBlockKey: hashKeyStdB64
    )
  }

  @Test("verifies and decodes a value signed by Go's securecookie (JSON serializer, no block key)")
  func decodesGoValue() throws {
    // Decode a few seconds after the embedded timestamp — well inside securecookie's 30-day default
    // decode bound (lifetime is unset, so UTIL-01's 30-day fallback applies on both sides).
    let m = try CookieManager(config: config(), now: { self.goTimestamp + 5 })
    let decoded = try m.decode(name: cookieName, from: goEncoded, as: Example.self)
    #expect(decoded == Example(name: "REPO-07 interop"))
  }

  @Test("the MAC is bound to the Go cookie name — a different name fails to verify")
  func nameBoundIntoMac() throws {
    let m = try CookieManager(config: config(), now: { self.goTimestamp + 5 })
    #expect(throws: CookieError.macInvalid) {
      _ = try m.decode(name: "different_name", from: goEncoded, as: Example.self)
    }
  }

  @Test("the Go value is rejected past the 30-day default decode window (UTIL-01)")
  func expiresPastDefaultWindow() throws {
    let thirtyDaysPlus = goTimestamp + 86_400 * 30 + 1
    let m = try CookieManager(config: config(), now: { thirtyDaysPlus })
    #expect(throws: CookieError.expired) {
      _ = try m.decode(name: cookieName, from: goEncoded, as: Example.self)
    }
  }

  @Test("a wrong hash key fails the MAC on the Go value")
  func wrongKeyRejectsGoValue() throws {
    var cfg = config()
    cfg.base64EncodedHashKey = Data("ADIFFERENT32CHARSECRETVALUE12345".utf8).base64EncodedString()
    let m = try CookieManager(config: cfg, now: { self.goTimestamp + 5 })
    #expect(throws: CookieError.macInvalid) {
      _ = try m.decode(name: cookieName, from: goEncoded, as: Example.self)
    }
  }
}
