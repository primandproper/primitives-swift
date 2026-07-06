import Foundation

/// The TOTP generation/verification seam, abstracting ``TOTP`` so a call site can depend on the
/// capability rather than the concrete CryptoKit-backed type. Ported from the `Verifier` interface in
/// platform-go's `authentication/totp` — widened to also expose **generation** (the piece an
/// authenticator-app UI needs, which the server-shaped Go interface omitted).
///
/// The time reference is injected via `at:` so tests can pin RFC 6238 vectors; the `Now` conveniences
/// (default-implemented below) read the wall clock at the edge, matching Go's `time.Now().UTC()`.
public protocol TOTPGenerator: Sendable {
  /// Generates the code for `secret` at `date`. Throws ``TOTPError/invalidSecret`` on a bad secret.
  func generate(secret: String, at date: Date) throws -> String

  /// Verifies `code` against `secret` at `date`, throwing ``TOTPError`` on an empty/invalid code or a
  /// malformed secret.
  func verify(code: String, secret: String, at date: Date) throws

  /// `Bool`-returning verification for control flow (does not distinguish empty from wrong). Throws
  /// only on a malformed secret.
  func isValid(code: String, secret: String, at date: Date) throws -> Bool
}

extension TOTPGenerator {
  /// Generates a code against the current wall clock.
  public func generateNow(secret: String) throws -> String {
    try generate(secret: secret, at: Date())
  }

  /// Verifies a code against the current wall clock.
  public func verifyNow(code: String, secret: String) throws {
    try verify(code: code, secret: secret, at: Date())
  }
}

/// ``TOTP`` is the live conformer — its `generate`/`verify`/`isValid` already match the seam exactly.
extension TOTP: TOTPGenerator {}
