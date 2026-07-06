import Foundation

/// A no-op ``JWTParsing``, the inert default for dependency injection when no real parser is wired.
///
/// Like ``NoopTOTPGenerator``, this fails safe: a verifier that silently accepted every token would be
/// an authentication bypass, so ``parse(_:at:)`` always throws ``JWTError/malformed``. It verifies no
/// signature and trusts no claim.
///
/// - Warning: not a bypass and not a real parser. Use only as a DI placeholder or in tests; never let
///   it stand in for a configured ``JWTParser``.
public struct NoopJWTParser: JWTParsing {
  public init() {}

  /// Rejects every token — a Noop has no key to verify against, so nothing can be trusted.
  public func parse(_ token: String, at date: Date) throws -> JWTClaims {
    throw JWTError.malformed
  }
}
