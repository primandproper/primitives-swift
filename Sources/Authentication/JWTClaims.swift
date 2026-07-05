import Foundation

/// The parsed claim set of a JWT, ported from platform-go's `tokens.Claims` interface.
///
/// Go exposes issuer-owned registered claims via typed accessors (`Subject`, `JTI`, `ExpiresAt`) and
/// application-specific claims via `Get` / `GetString`. This port mirrors that split: registered claims
/// are computed properties over the raw payload, and arbitrary claims are read with ``get(_:)`` /
/// ``string(_:)``.
///
/// - Note: Go's `Subject()`/`JTI()` return `""` for a missing claim and `GetString` returns
///   `("", false)`. Swift is more honest about absence: the registered accessors and ``string(_:)``
///   return `nil` when a claim is absent (or, for `string`, present-but-not-a-string), which is the
///   idiomatic `(_, ok)` translation.
public struct JWTClaims: Sendable, Equatable {
  /// The full decoded payload, keyed by claim name.
  public let raw: [String: JSONValue]

  public init(raw: [String: JSONValue]) {
    self.raw = raw
  }

  // MARK: - Registered claims (RFC 7519)

  /// The `sub` (subject) claim, or `nil` if absent / not a string. Mirrors Go's `Subject()`.
  public var subject: String? { string("sub") }

  /// The `jti` (JWT ID) claim, or `nil` if absent / not a string. Mirrors Go's `JTI()`.
  public var jti: String? { string("jti") }

  /// The `iss` (issuer) claim, or `nil` if absent / not a string.
  public var issuer: String? { string("iss") }

  /// The `exp` (expiration) claim as a `Date`, or `nil` if absent. Mirrors Go's `ExpiresAt()`
  /// (which returns the zero time when unset). `exp` is a JSON `NumericDate` — seconds since the Unix
  /// epoch.
  public var expiresAt: Date? { date("exp") }

  /// The `nbf` (not-before) claim as a `Date`, or `nil` if absent.
  public var notBefore: Date? { date("nbf") }

  /// The `iat` (issued-at) claim as a `Date`, or `nil` if absent.
  public var issuedAt: Date? { date("iat") }

  /// The `aud` (audience) claim, normalized to an array. RFC 7519 allows `aud` to be either a single
  /// string or an array of strings; both decode to a `[String]` here (empty if absent).
  public var audience: [String] {
    switch raw["aud"] {
    case .string(let value):
      return [value]
    case .array(let values):
      return values.compactMap(\.stringValue)
    default:
      return []
    }
  }

  // MARK: - Arbitrary claim access

  /// The raw value for `key`, or `nil` if absent. Mirrors Go's `Get(key) (any, bool)`.
  public func get(_ key: String) -> JSONValue? {
    raw[key]
  }

  /// The string value for `key`, or `nil` if absent or not a string. Mirrors Go's
  /// `GetString(key) (string, bool)`.
  public func string(_ key: String) -> String? {
    raw[key]?.stringValue
  }

  private func date(_ key: String) -> Date? {
    guard let seconds = raw[key]?.doubleValue else { return nil }
    return Date(timeIntervalSince1970: seconds)
  }
}
