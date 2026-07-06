import CryptoKit
import Foundation
import Testing

@testable import Authentication

/// REPO-11 + REPO-10: strict-rejection tests for the JWT parser — `alg:"none"`/empty signatures, strict
/// base64url segments, wrong-typed `exp`/`nbf`, non-string `aud` elements, a `crit` header, and the new
/// `leeway`.
@Suite("JWT — strict rejection (REPO-11 / REPO-10)")
struct JWTStrictnessTests {
  private let key = Data("HEREISA32CHARSECRETWHICHISMADEUP".utf8)
  private let now = Date(timeIntervalSince1970: 1_000_000)

  /// Signs an HS256 token, allowing a custom header (so `crit`/`alg` variants can be produced). The
  /// signature is computed correctly, so rejections come from the parser's validation, not a bad MAC.
  private func sign(
    header: [String: Any] = ["alg": "HS256", "typ": "JWT"],
    claims: [String: Any]
  ) -> String {
    let headerData = try! JSONSerialization.data(withJSONObject: header)
    let claimsData = try! JSONSerialization.data(withJSONObject: claims)
    let input = Base64URLNoPad.encode(headerData) + "." + Base64URLNoPad.encode(claimsData)
    let mac = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: SymmetricKey(data: key))
    return input + "." + Base64URLNoPad.encode(Data(mac))
  }

  private func parser(leeway: TimeInterval = 0) -> JWTParser {
    JWTParser(key: .hs256(secret: key), leeway: leeway)
  }

  // MARK: alg:"none" / empty signature (REPO-10)

  @Test("rejects an alg:\"none\" token")
  func algNone() {
    // A "none" alg can never match the HMAC key — refused before any verification.
    let header = ["alg": "none", "typ": "JWT"]
    let unsigned =
      Base64URLNoPad.encode(try! JSONSerialization.data(withJSONObject: header)) + "."
      + Base64URLNoPad.encode(
        try! JSONSerialization.data(withJSONObject: ["sub": "u", "exp": 2_000_000]))
      + "."  // empty signature segment, as an alg:none token carries
    #expect(throws: JWTError.algorithmMismatch(expected: "HS256", found: "none")) {
      _ = try parser().parse(unsigned, at: now)
    }
  }

  @Test("rejects an HS256-labelled token with an empty signature")
  func emptySignature() {
    let input =
      Base64URLNoPad.encode(
        try! JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"]))
      + "."
      + Base64URLNoPad.encode(
        try! JSONSerialization.data(withJSONObject: ["sub": "u", "exp": 2_000_000]))
    let noSig = input + "."
    #expect(throws: JWTError.invalidSignature) {
      _ = try parser().parse(noSig, at: now)
    }
  }

  // MARK: strict base64url segments (REPO-11)

  @Test("rejects a token whose payload segment carries a non-URL-safe character")
  func nonUrlSafeSegment() {
    let good = sign(claims: ["sub": "u", "exp": 2_000_000])
    var parts = good.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    // Inject a '+' (standard alphabet, not URL-safe) into the payload — strict decode must reject it.
    parts[1] = "+" + parts[1]
    #expect(throws: JWTError.malformed) {
      _ = try parser().parse(parts.joined(separator: "."), at: now)
    }
  }

  // MARK: wrong-typed exp / nbf (REPO-11)

  @Test("treats a string-typed exp as malformed, not absent")
  func stringExpIsMalformed() {
    let token = sign(claims: ["sub": "u", "exp": "2000000"])
    #expect(throws: JWTError.malformed) {
      _ = try parser().parse(token, at: now)
    }
  }

  @Test("treats a string-typed nbf as malformed, not absent")
  func stringNbfIsMalformed() {
    let token = sign(claims: ["sub": "u", "exp": 2_000_000, "nbf": "500000"])
    #expect(throws: JWTError.malformed) {
      _ = try parser().parse(token, at: now)
    }
  }

  // MARK: non-string aud elements (REPO-11)

  @Test("rejects an aud array containing a non-string element")
  func nonStringAudElement() {
    // JSONSerialization keeps the mixed [String, Int] array; a numeric aud element must be rejected,
    // not silently dropped.
    let token = sign(claims: ["sub": "u", "exp": 2_000_000, "aud": ["good", 42] as [Any]])
    #expect(throws: JWTError.malformed) {
      _ = try parser().parse(token, at: now)
    }
  }

  @Test("still accepts a well-formed all-string aud array")
  func allStringAudStillWorks() throws {
    let token = sign(claims: ["sub": "u", "exp": 2_000_000, "aud": ["a", "b"]])
    let claims = try parser().parse(token, at: now)
    #expect(claims.audience == ["a", "b"])
  }

  // MARK: crit header (REPO-11)

  @Test("rejects a token carrying a crit header")
  func critHeaderRejected() {
    let token = sign(
      header: ["alg": "HS256", "typ": "JWT", "crit": ["exp"]],
      claims: ["sub": "u", "exp": 2_000_000])
    #expect(throws: JWTError.unsupportedCriticalHeader) {
      _ = try parser().parse(token, at: now)
    }
  }

  // MARK: leeway (REPO-11 optional)

  @Test("leeway tolerates a small clock drift past exp")
  func leewayForExp() throws {
    let token = sign(claims: ["sub": "u", "exp": 1_000])
    let justAfter = Date(timeIntervalSince1970: 1_005)
    // No leeway: expired. With 10s leeway: still valid.
    #expect(throws: JWTError.expired) {
      _ = try parser(leeway: 0).parse(token, at: justAfter)
    }
    #expect(try parser(leeway: 10).parse(token, at: justAfter).subject == "u")
  }

  @Test("leeway tolerates a small clock drift before nbf")
  func leewayForNbf() throws {
    let token = sign(claims: ["sub": "u", "exp": 2_000_000, "nbf": 1_000])
    let justBefore = Date(timeIntervalSince1970: 995)
    #expect(throws: JWTError.notYetValid) {
      _ = try parser(leeway: 0).parse(token, at: justBefore)
    }
    #expect(try parser(leeway: 10).parse(token, at: justBefore).subject == "u")
  }
}

/// REPO-11 / REPO-10: direct strict-alphabet tests for the unpadded base64url codec JWS segments use.
@Suite("Base64URLNoPad — strict decode (REPO-11)")
struct Base64URLNoPadStrictTests {
  @Test("round-trips the URL-safe alphabet it emits (no padding)")
  func roundTrips() {
    let data = Data([0xFB, 0xFF, 0x00])
    let encoded = Base64URLNoPad.encode(data)  // "-_8A", '-' and '_', no '='
    #expect(!encoded.contains("="))
    #expect(Base64URLNoPad.decode(encoded) == data)
  }

  @Test("rejects the standard-alphabet + and /")
  func rejectsStandardAlphabet() {
    #expect(Base64URLNoPad.decode("ab+c") == nil)
    #expect(Base64URLNoPad.decode("ab/c") == nil)
  }

  @Test("rejects any = (RawURLEncoding is unpadded)")
  func rejectsPadding() {
    #expect(Base64URLNoPad.decode("YQ==") == nil)
    #expect(Base64URLNoPad.decode("YWJj=") == nil)
  }

  @Test("rejects whitespace and other non-alphabet bytes")
  func rejectsGarbage() {
    #expect(Base64URLNoPad.decode("ab cd") == nil)
    #expect(Base64URLNoPad.decode("ab.cd") == nil)
  }

  @Test("an empty string decodes to empty data (so an empty JWS signature reaches the alg check)")
  func emptyIsEmpty() {
    #expect(Base64URLNoPad.decode("") == Data())
  }
}
