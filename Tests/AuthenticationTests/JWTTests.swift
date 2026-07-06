import CryptoKit
import Foundation
import Security
import Testing

@testable import Authentication

// MARK: - Test signing helpers (issuance is server-side and not part of the module; these mint tokens
// only so the client-side parse/verify path can be exercised).

private func makeUnsignedInput(header: [String: Any], claims: [String: Any]) -> String {
  let headerData = try! JSONSerialization.data(withJSONObject: header)
  let claimsData = try! JSONSerialization.data(withJSONObject: claims)
  return Base64URLNoPad.encode(headerData) + "." + Base64URLNoPad.encode(claimsData)
}

private func signHS256(claims: [String: Any], key: Data, alg: String = "HS256") -> String {
  let input = makeUnsignedInput(header: ["alg": alg, "typ": "JWT"], claims: claims)
  let mac = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: SymmetricKey(data: key))
  return input + "." + Base64URLNoPad.encode(Data(mac))
}

@Suite("JWT parsing — HS256 (platform-go wire parity)")
struct JWTHS256Tests {
  // A genuine token minted by platform-go's HS256 signer (from its jwt_test.go), with the matching
  // 32-byte signing key. Verifying it here proves the Swift parser is byte-compatible with the Go
  // origin's golang-jwt output.
  private let goToken =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJUZXN0X2p3dFNpZ25lcl9Jc3N1ZUpXVC9zdGFuZGFyZCIsImV4cCI6MTcyNzU3MDU0OCwiaWF0IjoxNzI3NTY5OTQ4LCJpc3MiOiJkaW5uZXJkb25lYmV0dGVyIiwianRpIjoiY3JzYTA3NnRnM3FkdG1jY3E5MTAiLCJuYmYiOjE3Mjc1Njk4ODgsInN1YiI6ImNyc2EwNzZ0ZzNxZHRtY2NxOTBnIn0.tMASrQBoYAq4n1iwOElLqUQsYOARX5T1qxo8RKhvaAg"
  private let key = Data("HEREISA32CHARSECRETWHICHISMADEUP".utf8)
  private let issuer = "dinnerdonebetter"
  private let audience = "Test_jwtSigner_IssueJWT/standard"
  // Between the token's nbf (1727569888) and exp (1727570548).
  private let validInstant = Date(timeIntervalSince1970: 1_727_570_000)

  private func parser() -> JWTParser {
    JWTParser(
      key: .hs256(secret: key), expectedIssuer: issuer, expectedAudience: audience)
  }

  @Test("verifies the signature and reads registered + custom claims")
  func happyPath() throws {
    let claims = try parser().parse(goToken, at: validInstant)
    #expect(claims.subject == "crsa076tg3qdtmccq90g")
    #expect(claims.jti == "crsa076tg3qdtmccq910")
    #expect(claims.issuer == issuer)
    #expect(claims.audience == [audience])
    #expect(claims.expiresAt == Date(timeIntervalSince1970: 1_727_570_548))
    // Arbitrary-claim accessors mirror Go's Get / GetString.
    #expect(claims.string("iss") == issuer)
    #expect(claims.get("nbf")?.doubleValue == 1_727_569_888)
    #expect(claims.string("does_not_exist") == nil)
    #expect(claims.get("does_not_exist") == nil)
  }

  @Test("rejects the token once it has expired")
  func expired() {
    let afterExpiry = Date(timeIntervalSince1970: 1_727_570_600)
    #expect(throws: JWTError.expired) {
      _ = try parser().parse(goToken, at: afterExpiry)
    }
  }

  @Test("rejects a mismatched issuer")
  func wrongIssuer() {
    let p = JWTParser(
      key: .hs256(secret: key), expectedIssuer: "someone-else", expectedAudience: audience)
    #expect(throws: JWTError.invalidIssuer) {
      _ = try p.parse(goToken, at: validInstant)
    }
  }

  @Test("rejects a mismatched audience")
  func wrongAudience() {
    let p = JWTParser(
      key: .hs256(secret: key), expectedIssuer: issuer, expectedAudience: "other-service")
    #expect(throws: JWTError.invalidAudience) {
      _ = try p.parse(goToken, at: validInstant)
    }
  }

  @Test("rejects a tampered signature")
  func tamperedSignature() {
    // Flip the FIRST character of the signature segment. The final base64url char of a 32-byte
    // HMAC carries only 2 significant bits (4 are dropped padding), so flipping it can decode to the
    // same bytes; the first char's bits are all significant, so this genuinely alters the signature.
    var parts = goToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    var sig = Array(parts[2])
    sig[0] = sig[0] == "A" ? "B" : "A"
    parts[2] = String(sig)
    let tampered = parts.joined(separator: ".")
    #expect(throws: JWTError.invalidSignature) {
      _ = try parser().parse(tampered, at: validInstant)
    }
  }

  @Test("rejects a token signed under a different key")
  func wrongKey() {
    let p = JWTParser(
      key: .hs256(secret: Data("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX".utf8)),
      expectedIssuer: issuer, expectedAudience: audience)
    #expect(throws: JWTError.invalidSignature) {
      _ = try p.parse(goToken, at: validInstant)
    }
  }
}

@Suite("JWT parsing — claim validation edges")
struct JWTClaimValidationTests {
  private let key = Data("HEREISA32CHARSECRETWHICHISMADEUP".utf8)
  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func parser(requireExpiration: Bool = true) -> JWTParser {
    JWTParser(key: .hs256(secret: key), requireExpiration: requireExpiration)
  }

  @Test("rejects a not-yet-valid token (nbf in the future)")
  func notYetValid() {
    let token = signHS256(
      claims: ["sub": "u", "exp": 2_000_000, "nbf": 1_500_000], key: key)
    #expect(throws: JWTError.notYetValid) {
      _ = try parser().parse(token, at: now)
    }
  }

  @Test("rejects a token missing the required exp claim")
  func missingExp() {
    let token = signHS256(claims: ["sub": "u"], key: key)
    #expect(throws: JWTError.missingExpiration) {
      _ = try parser().parse(token, at: now)
    }
  }

  @Test("accepts a token without exp when expiration is not required")
  func expNotRequired() throws {
    let token = signHS256(claims: ["sub": "u"], key: key)
    let claims = try parser(requireExpiration: false).parse(token, at: now)
    #expect(claims.subject == "u")
  }

  @Test("normalizes an array-valued aud claim")
  func arrayAudience() throws {
    let token = signHS256(
      claims: ["sub": "u", "exp": 2_000_000, "aud": ["a", "b"]], key: key)
    let p = JWTParser(key: .hs256(secret: key), expectedAudience: "b")
    let claims = try p.parse(token, at: now)
    #expect(claims.audience == ["a", "b"])
  }

  @Test("rejects an alg header that does not match the key (algorithm confusion)")
  func algorithmMismatch() {
    // Header claims ES256 but the key is HMAC — must be refused before any verification.
    let token = signHS256(claims: ["sub": "u", "exp": 2_000_000], key: key, alg: "ES256")
    #expect(throws: JWTError.algorithmMismatch(expected: "HS256", found: "ES256")) {
      _ = try parser().parse(token, at: now)
    }
  }

  @Test("rejects structurally malformed tokens")
  func malformed() {
    for bad in ["not-a-jwt", "only.two", "a.b.c.d", "!!!.???.###"] {
      #expect(throws: JWTError.malformed) {
        _ = try parser().parse(bad, at: now)
      }
    }
  }
}

@Suite("JWT parsing — asymmetric schemes")
struct JWTAsymmetricTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  @Test("verifies an ES256 signature (P-256)")
  func es256() throws {
    let privateKey = P256.Signing.PrivateKey()
    let input = makeUnsignedInput(
      header: ["alg": "ES256", "typ": "JWT"], claims: ["sub": "u", "exp": 2_000_000])
    let signature = try privateKey.signature(for: Data(input.utf8))
    // JWS carries the raw r‖s form, not DER.
    let token = input + "." + Base64URLNoPad.encode(signature.rawRepresentation)

    let parser = JWTParser(key: .ecdsaP256(privateKey.publicKey))
    let claims = try parser.parse(token, at: now)
    #expect(claims.subject == "u")

    // A different key must not verify.
    let other = JWTParser(key: .ecdsaP256(P256.Signing.PrivateKey().publicKey))
    #expect(throws: JWTError.invalidSignature) {
      _ = try other.parse(token, at: now)
    }
  }

  @Test("verifies an RS256 signature (RSA PKCS#1 v1.5)")
  func rs256() throws {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits as String: 2048,
    ]
    var error: Unmanaged<CFError>?
    let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    let publicKey = try #require(SecKeyCopyPublicKey(privateKey))

    let input = makeUnsignedInput(
      header: ["alg": "RS256", "typ": "JWT"], claims: ["sub": "u", "exp": 2_000_000])
    let signature =
      try #require(
        SecKeyCreateSignature(
          privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(input.utf8) as CFData, &error)
      ) as Data
    let token = input + "." + Base64URLNoPad.encode(signature)

    let parser = JWTParser(key: .rsa(publicKey))
    let claims = try parser.parse(token, at: now)
    #expect(claims.subject == "u")
  }
}

// MARK: - Sendability regression (CRY-11)

/// An actor that holds a ``JWTParser`` as stored state. This only type-checks because
/// ``JWTVerificationKey`` (and therefore ``JWTParser``) conforms to `Sendable` — before CRY-11 the
/// `rsa` case's `SecKey` made the type non-`Sendable`, and the compiler would have rejected storing a
/// parser here with "non-sendable type 'JWTParser' in actor-isolated property".
private actor TokenVerifier {
  private let parser: JWTParser

  init(parser: JWTParser) {
    self.parser = parser
  }

  func verify(_ token: String, at date: Date) throws -> JWTClaims {
    try parser.parse(token, at: date)
  }
}

@Suite("JWTParser is Sendable (CRY-11)")
struct JWTParserSendableTests {
  private let key = Data("HEREISA32CHARSECRETWHICHISMADEUP".utf8)
  private let now = Date(timeIntervalSince1970: 1_000_000)

  @Test("an HS256 parser can be stored in an actor and used across the isolation boundary")
  func storedInActor() async throws {
    let token = signHS256(claims: ["sub": "actor-user", "exp": 2_000_000], key: key)
    let parser = JWTParser(key: .hs256(secret: key))
    let verifier = TokenVerifier(parser: parser)

    let claims = try await verifier.verify(token, at: now)
    #expect(claims.subject == "actor-user")
  }

  @Test("an HS256 parser can cross into a detached, non-isolated Task via a @Sendable closure")
  func capturedInSendableTask() async throws {
    let token = signHS256(claims: ["sub": "task-user", "exp": 2_000_000], key: key)
    let parser = JWTParser(key: .hs256(secret: key))
    let deadline = now

    // `Task.detached` requires its closure to be `@Sendable`; capturing `parser` here would not
    // compile before CRY-11.
    let claims = try await Task.detached { @Sendable in
      try parser.parse(token, at: deadline)
    }.value

    #expect(claims.subject == "task-user")
  }
}
