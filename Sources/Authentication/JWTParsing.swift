import Foundation

/// The JWT parse/verify seam, abstracting ``JWTParser`` so a call site can depend on the capability
/// rather than the concrete CryptoKit/Security-backed type. Ported from the client-relevant half of
/// platform-go's `authentication/tokens` — the `ParseToken` path.
///
/// The reference time is injected via `at:` so tests can pin fixed instants against forged expiry; the
/// ``parse(_:)`` convenience (default-implemented below) reads `Date()` at the edge.
public protocol JWTParsing: Sendable {
  /// Parses and verifies `token` against the reference time `date`, returning its claims on success.
  /// - Throws: ``JWTError`` on any structural, signature, or claim-validation failure.
  func parse(_ token: String, at date: Date) throws -> JWTClaims
}

extension JWTParsing {
  /// Parses and verifies `token` against the current wall clock.
  public func parse(_ token: String) throws -> JWTClaims {
    try parse(token, at: Date())
  }
}

/// ``JWTParser`` is the live conformer — its `parse(_:at:)` already matches the seam exactly.
extension JWTParser: JWTParsing {}
