import Foundation

/// The signing/verification seam ``CookieManager`` provides, extracted so callers can depend on the
/// behavior rather than the concrete type — and so a ``NoopCookieManaging`` / ``MockCookieManaging`` can
/// stand in for tests and disabled configurations.
///
/// platform-go's `cookies` package has no interface (callers hold the concrete `*Manager`), so this
/// protocol has no Go analogue — it exists because this port's settled rule is that every seam ships a
/// Noop and a Mock (REPO-05), which requires a protocol to conform them to. ``CookieManager`` itself is
/// the production conformer and keeps its exact signatures, so extracting the protocol is source-neutral
/// for existing callers.
///
/// The requirements carry ``CookieManager``'s typed `throws(CookieError)` and its generic value
/// parameters unchanged: `encode`/`buildCookie` take `some Encodable`, and `decode` is generic over the
/// `Decodable` result. These are all expressible as protocol requirements, so `any CookieManaging` can be
/// used behind an existential wherever the concrete manager was.
public protocol CookieManaging: Sendable {
  /// Serializes and signs `value`, returning the encoded cookie value. See
  /// ``CookieManager/encode(name:_:)``.
  func encode(name: String, _ value: some Encodable) throws(CookieError) -> String

  /// Verifies and deserializes an encoded cookie value. See ``CookieManager/decode(name:from:as:)``.
  func decode<Value: Decodable>(
    name: String, from encoded: String, as type: Value.Type
  ) throws(CookieError) -> Value

  /// Encodes `value` into a ready-to-store `HTTPCookie`. See ``CookieManager/buildCookie(name:_:)``.
  func buildCookie(name: String, _ value: some Encodable) throws(CookieError) -> HTTPCookie
}

extension CookieManaging {
  /// Source-compatible convenience mirroring ``CookieManager/decode(name:from:as:)``'s defaulted type
  /// argument, which a protocol requirement can't carry.
  public func decode<Value: Decodable>(
    name: String, from encoded: String, as _: Value.Type = Value.self
  ) throws(CookieError) -> Value {
    try decode(name: name, from: encoded, as: Value.self)
  }
}

extension CookieManager: CookieManaging {}
