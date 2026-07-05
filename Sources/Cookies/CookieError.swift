import Foundation

/// Errors thrown while building a ``CookieManager`` or encoding/decoding a signed cookie value.
///
/// platform-go surfaces these across several layers: `perrors.ErrNilInputProvided` and wrapped
/// `fmt.Errorf` strings from `NewCookieManager`, ozzo-validation failures from
/// `Config.ValidateWithContext`, and `gorilla/securecookie`'s own `ErrMacInvalid` /
/// `errTimestampExpired` sentinels. Swift folds them into one typed enum — the idiomatic shape for a
/// closed set of failure modes — thrown via typed `throws(CookieError)`.
///
/// Note the deliberate omission of a "nil config" case: Go guards against a `nil *Config`, but Swift's
/// non-optional `CookieConfig` makes that unrepresentable, so the check disappears.
public enum CookieError: Error, Equatable, Sendable {
  /// The config failed validation. The associated string is a human-readable reason (never the key
  /// material — see the secret-safety note on ``invalidHashKey``). Mirrors the several
  /// `Config.ValidateWithContext` failures.
  case invalidConfiguration(String)

  /// The configured `base64EncodedHashKey` was not valid standard base64. Mirrors Go's
  /// `decoding HashKey` error. Carries no payload so the secret key material never reaches a log.
  case invalidHashKey

  /// The configured `base64EncodedBlockKey` was not valid standard base64. Mirrors Go's
  /// `decoding BlockKey` error. See the note on encryption in ``CookieManager``: the block key is
  /// validated for parity but the AES-CTR encryption it feeds is not ported.
  case invalidBlockKey

  /// The value could not be JSON-serialized before signing. Wraps a `JSONEncoder` failure (the
  /// analogue of Go's serializer error path).
  case serializationFailed

  /// The decoded payload could not be JSON-deserialized into the requested type. Wraps a
  /// `JSONDecoder` failure.
  case deserializationFailed

  /// The encoded value was not well-formed: not valid base64, or missing the `date|payload|mac`
  /// structure. Mirrors `gorilla/securecookie`'s base64 decode error and `ErrMacInvalid`'s
  /// "not enough parts" branch.
  case malformedValue

  /// The message authentication code did not verify — the value was tampered with, signed with a
  /// different hash key, or presented under a different cookie name (the name is bound into the MAC).
  /// Mirrors `securecookie.ErrMacInvalid`.
  case macInvalid

  /// The signed timestamp is older than the configured lifetime. Mirrors
  /// `securecookie`'s `errTimestampExpired`.
  case expired

  /// The signed timestamp was not a parseable integer. Mirrors `securecookie`'s `errTimestampInvalid`.
  case timestampInvalid

  /// ``CookieManager/buildCookie(name:_:)`` requires a non-empty domain: unlike Go's `http.Cookie`
  /// (which treats an empty domain as "the current host"), Foundation's `HTTPCookie` cannot be
  /// constructed without a domain or origin URL.
  case missingDomain

  /// `HTTPCookie(properties:)` returned nil despite a non-empty domain — an unexpected construction
  /// failure. Kept distinct from ``missingDomain`` so the common, explainable case has its own signal.
  case cookieConstructionFailed
}

extension CookieError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let reason):
      return "invalid cookie configuration: \(reason)"
    case .invalidHashKey:
      return "hash key is not valid base64"
    case .invalidBlockKey:
      return "block key is not valid base64"
    case .serializationFailed:
      return "failed to serialize cookie value"
    case .deserializationFailed:
      return "failed to deserialize cookie value"
    case .malformedValue:
      return "cookie value is malformed"
    case .macInvalid:
      return "cookie signature is invalid"
    case .expired:
      return "cookie has expired"
    case .timestampInvalid:
      return "cookie timestamp is invalid"
    case .missingDomain:
      return "building an HTTPCookie requires a non-empty domain"
    case .cookieConstructionFailed:
      return "failed to construct HTTPCookie"
    }
  }
}
