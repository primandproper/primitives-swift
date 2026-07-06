import CryptoKit
import Foundation
import Security

/// Errors thrown while parsing/verifying a JWT, ported from platform-go's `tokens` sentinels
/// (`ErrTokenExpired`, `ErrTokenNotYetValid`, `ErrInvalidAudience`, `ErrInvalidIssuer`) plus the
/// structural/signature failures golang-jwt surfaces during `Parse`.
public enum JWTError: Error, Equatable, Sendable {
  /// The token was not a well-formed `header.payload.signature` triple, or a segment was not valid
  /// base64url / JSON.
  case malformed
  /// The token's `alg` header did not match the configured verification key. Mirrors golang-jwt's
  /// "unexpected signing method" rejection — the primary defense against algorithm-confusion attacks.
  case algorithmMismatch(expected: String, found: String)
  /// The signature did not verify against the key. Mirrors a failed `keyFunc`/verification in Go.
  case invalidSignature
  /// The `exp` claim is in the past. Mirrors Go's `ErrTokenExpired`.
  case expired
  /// The `exp` claim was required but absent. Mirrors golang-jwt's `ErrTokenRequiredClaimMissing`
  /// (the signer parses `WithExpirationRequired()`).
  case missingExpiration
  /// The `nbf` claim is in the future. Mirrors Go's `ErrTokenNotYetValid`.
  case notYetValid
  /// The `iss` claim did not match the expected issuer. Mirrors Go's `ErrInvalidIssuer`.
  case invalidIssuer
  /// The `aud` claim did not contain the expected audience. Mirrors Go's `ErrInvalidAudience`.
  case invalidAudience
}

extension JWTError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .malformed: return "token is malformed"
    case .algorithmMismatch(let expected, let found):
      return "unexpected signing method: \(found) (expected \(expected))"
    case .invalidSignature: return "token signature is invalid"
    case .expired: return "token is expired"
    case .missingExpiration: return "token is missing required expiration claim"
    case .notYetValid: return "token is not yet valid"
    case .invalidIssuer: return "token issuer is not valid"
    case .invalidAudience: return "token audience is not valid"
    }
  }
}

/// The signature scheme a ``JWTVerificationKey`` verifies, and the `alg` header value it pins.
public enum JWTAlgorithm: String, Sendable {
  /// HMAC-SHA256 — what platform-go's `jwt.NewJWTSigner` uses (`jwt.SigningMethodHS256`).
  case hs256 = "HS256"
  /// ECDSA over P-256 with SHA-256.
  case es256 = "ES256"
  /// RSASSA-PKCS1-v1_5 with SHA-256.
  case rs256 = "RS256"
}

/// The material used to verify a JWT signature, one variant per supported scheme.
///
/// platform-go only ever signs/verifies with **HS256** (a shared `[]byte` signing key), so ``hmac`` is
/// the wire-faithful path. ``ecdsaP256`` and ``rsa`` are added because they map cleanly onto CryptoKit
/// (`P256`) and Security (`SecKey`) respectively and are the other two schemes a client realistically
/// meets from an asymmetric identity provider — but they have no counterpart in the Go origin.
///
/// - Note: `Sendable` conformance here is `@unchecked`: the `rsa` case wraps a `SecKey`, a
///   CoreFoundation type the compiler cannot verify as `Sendable`. This is sound in practice —
///   `SecKey` is immutable once created, is never mutated by this type, and is used exclusively as
///   the input to `SecKeyVerifySignature`, a synchronous, read-only verification call that Apple's
///   Security framework treats as safe to invoke from multiple threads/queues concurrently. No
///   mutable state is shared or crosses an isolation boundary, so treating this type (and the
///   ``JWTParser`` that stores it) as `Sendable` does not introduce a data race.
public enum JWTVerificationKey: @unchecked Sendable {
  /// HS256 shared secret. The verifier recomputes HMAC-SHA256 over the signing input.
  case hmac(SymmetricKey)
  /// ES256 public key.
  case ecdsaP256(P256.Signing.PublicKey)
  /// RS256 public key (an RSA `SecKey`, e.g. built from a certificate or JWK modulus/exponent).
  case rsa(SecKey)

  /// Convenience for the Go-native path: an HS256 key from raw secret bytes.
  public static func hs256(secret: Data) -> JWTVerificationKey {
    .hmac(SymmetricKey(data: secret))
  }

  var algorithm: JWTAlgorithm {
    switch self {
    case .hmac: return .hs256
    case .ecdsaP256: return .es256
    case .rsa: return .rs256
    }
  }
}

/// Parses and verifies compact JWTs, ported from the client-relevant half of platform-go's
/// `authentication/tokens/jwt` — the `ParseToken` path. (Issuance/signing, `IssueToken`, is server-side
/// and deliberately not ported; see ``Authentication``.)
///
/// Verification follows the same rules the Go signer enforces via golang-jwt options: the `alg` header
/// must match the configured key (rejecting algorithm confusion), the signature must verify, `exp` is
/// required and must be in the future, `nbf` must not be in the future, and — when configured — `iss`
/// and `aud` must match.
///
/// - Important: The reference time for `exp`/`nbf` is **injected** via `at:` so tests can pin fixed
///   instants against forged expiry. ``parse(_:)`` reads `Date()` at the edge.
///
/// - Note: `Sendable` by inheritance from ``JWTVerificationKey``'s `@unchecked Sendable`
///   conformance; all other stored properties are plain value types. This lets a parser (HMAC/ES256
///   included) be captured across isolation boundaries — stored in an actor, or handed to a `Task` /
///   `@Sendable` closure — even though the `.rsa` case internally holds a non-`Sendable` `SecKey`.
public struct JWTParser: Sendable {
  private let key: JWTVerificationKey
  private let expectedIssuer: String?
  private let expectedAudience: String?
  private let requireExpiration: Bool

  /// - Parameters:
  ///   - key: the verification material; its scheme pins the accepted `alg` header.
  ///   - expectedIssuer: if non-nil, `iss` must equal this. Matches the Go signer's `WithIssuer`.
  ///   - expectedAudience: if non-nil, `aud` must contain this. Matches the Go signer's `WithAudience`.
  ///   - requireExpiration: if `true` (default), a token without `exp` is rejected, matching the Go
  ///     signer's `WithExpirationRequired`.
  public init(
    key: JWTVerificationKey,
    expectedIssuer: String? = nil,
    expectedAudience: String? = nil,
    requireExpiration: Bool = true
  ) {
    self.key = key
    self.expectedIssuer = expectedIssuer
    self.expectedAudience = expectedAudience
    self.requireExpiration = requireExpiration
  }

  /// Parses and verifies `token` against the reference time `date`, returning its claims on success.
  public func parse(_ token: String, at date: Date) throws -> JWTClaims {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3 else { throw JWTError.malformed }

    let headerSegment = String(segments[0])
    let payloadSegment = String(segments[1])
    let signatureSegment = String(segments[2])

    guard
      let headerData = Base64URLNoPad.decode(headerSegment),
      let payloadData = Base64URLNoPad.decode(payloadSegment),
      let signature = Base64URLNoPad.decode(signatureSegment)
    else {
      throw JWTError.malformed
    }

    try verifyAlgorithm(headerData: headerData)

    // The signing input is the raw, still-encoded "header.payload" ASCII, per RFC 7515.
    let signingInput = Data((headerSegment + "." + payloadSegment).utf8)
    guard verifySignature(signature, over: signingInput) else {
      throw JWTError.invalidSignature
    }

    let claims = try decodeClaims(payloadData)
    try validateClaims(claims, at: date)
    return claims
  }

  /// Convenience parsing against the current wall clock.
  public func parse(_ token: String) throws -> JWTClaims {
    try parse(token, at: Date())
  }

  // MARK: - Steps

  private func verifyAlgorithm(headerData: Data) throws {
    struct Header: Decodable { let alg: String }
    guard let header = try? JSONDecoder().decode(Header.self, from: headerData) else {
      throw JWTError.malformed
    }
    let expected = key.algorithm.rawValue
    guard header.alg == expected else {
      throw JWTError.algorithmMismatch(expected: expected, found: header.alg)
    }
  }

  private func verifySignature(_ signature: Data, over signingInput: Data) -> Bool {
    switch key {
    case .hmac(let symmetricKey):
      let expected = CryptoKit.HMAC<SHA256>.authenticationCode(for: signingInput, using: symmetricKey)
      return constantTimeEqual(Array(expected), Array(signature))

    case .ecdsaP256(let publicKey):
      // JWS ES256 signatures are the raw r‖s concatenation (RFC 7518 §3.4), which is exactly
      // CryptoKit's `rawRepresentation`.
      guard let ecdsaSignature = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
        return false
      }
      return publicKey.isValidSignature(ecdsaSignature, for: signingInput)

    case .rsa(let secKey):
      var error: Unmanaged<CFError>?
      let ok = SecKeyVerifySignature(
        secKey,
        .rsaSignatureMessagePKCS1v15SHA256,
        signingInput as CFData,
        signature as CFData,
        &error)
      error?.release()
      return ok
    }
  }

  private func decodeClaims(_ payloadData: Data) throws -> JWTClaims {
    guard let raw = try? JSONDecoder().decode([String: JSONValue].self, from: payloadData) else {
      throw JWTError.malformed
    }
    return JWTClaims(raw: raw)
  }

  private func validateClaims(_ claims: JWTClaims, at date: Date) throws {
    // Order mirrors golang-jwt's validator: expiry first, then not-before, then issuer/audience.
    if let expiresAt = claims.expiresAt {
      // Valid only while `date` is strictly before `exp`; at/after `exp` the token is expired.
      if !(date < expiresAt) { throw JWTError.expired }
    } else if requireExpiration {
      throw JWTError.missingExpiration
    }

    if let notBefore = claims.notBefore, date < notBefore {
      throw JWTError.notYetValid
    }

    if let expectedIssuer, claims.issuer != expectedIssuer {
      throw JWTError.invalidIssuer
    }

    if let expectedAudience, !claims.audience.contains(expectedAudience) {
      throw JWTError.invalidAudience
    }
  }
}
