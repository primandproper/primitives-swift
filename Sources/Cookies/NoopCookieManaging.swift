import Foundation

/// A ``CookieManaging`` that mints nothing and verifies nothing — the always-safe fallback for a
/// disabled or unconfigured cookie layer, in the spirit of ``NoopCircuitBreaker`` and
/// ``NoopEventStream``.
///
/// There is no platform-go analogue (Go has no cookie interface), so this defines its own inert
/// contract: ``encode(name:_:)`` returns the empty string (no signed token is produced), while
/// ``decode(name:from:as:)`` and ``buildCookie(name:_:)`` throw — a no-op *cannot* fabricate a typed
/// value out of nothing, nor a domain-bound `HTTPCookie`, so refusing is the honest inert behavior
/// rather than returning a bogus success. Use it where a `CookieManaging` is required but signing is
/// switched off; a caller that actually needs to mint or verify cookies must inject a ``CookieManager``.
public struct NoopCookieManaging: CookieManaging {
  public init() {}

  /// Returns the empty string without signing anything.
  public func encode(name: String, _ value: some Encodable) throws(CookieError) -> String {
    ""
  }

  /// Always throws ``CookieError/malformedValue``: a no-op holds no key and can't verify or synthesize a
  /// typed value.
  public func decode<Value: Decodable>(
    name: String, from encoded: String, as _: Value.Type
  ) throws(CookieError) -> Value {
    throw .malformedValue
  }

  /// Always throws ``CookieError/missingDomain``: a no-op carries no config, so it has no domain to bind
  /// an `HTTPCookie` to.
  public func buildCookie(name: String, _ value: some Encodable) throws(CookieError) -> HTTPCookie {
    throw .missingDomain
  }
}
