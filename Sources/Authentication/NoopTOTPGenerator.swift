import Foundation

/// A no-op ``TOTPGenerator``, the inert default for dependency injection when no real TOTP is wired.
///
/// Unlike a passthrough noop, a *verifier* must fail safe: an unconfigured second factor that silently
/// "succeeds" would be an authentication bypass. So this Noop verifies **nothing** — ``verify`` always
/// throws (``TOTPError/codeRequired`` for an empty code, ``TOTPError/invalidCode`` otherwise) and
/// ``isValid`` always returns `false`. ``generate`` returns a zero-filled placeholder of the default
/// digit count.
///
/// - Warning: not a bypass and not a real generator. Use only as a DI placeholder or in tests; never
///   let it stand in for a configured ``TOTP``.
public struct NoopTOTPGenerator: TOTPGenerator {
  /// Digit count for the zero-filled placeholder ``generate`` returns. RFC 6238 default: 6.
  public let digits: Int

  public init(digits: Int = 6) {
    precondition(digits > 0 && digits <= 9, "TOTP digits must be 1...9")
    self.digits = digits
  }

  /// Returns a zero-filled placeholder (`"000000"` by default) — it validates against nothing.
  public func generate(secret: String, at date: Date) -> String {
    String(repeating: "0", count: digits)
  }

  public func verify(code: String, secret: String, at date: Date) throws {
    if code.isEmpty { throw TOTPError.codeRequired }
    throw TOTPError.invalidCode
  }

  public func isValid(code: String, secret: String, at date: Date) -> Bool { false }
}
