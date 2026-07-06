import Foundation
import os

/// A recording ``CookieManaging`` test double: it captures every call for later inspection and performs a
/// real — but **unsigned** — JSON round-trip so a test can drive encode/decode logic without provisioning
/// key material.
///
/// Go's `cookies` package ships no mock (it has no interface), so this is a port-native recorder in the
/// REPO-05 mold, with `*Calls` arrays a test asserts against (mirroring the moq `…Calls()` shape used by
/// ``EventReporterMock`` / ``FeatureFlagManagerMock``). It's a lock-backed `final class` rather than an
/// `actor` because ``CookieManaging``'s requirements are *synchronous* (typed `throws(CookieError)`, no
/// `async`) to match ``CookieManager`` exactly — an actor's `async` methods couldn't satisfy them — so an
/// `OSAllocatedUnfairLock` guards the recorded calls instead.
///
/// **The round-trip is deliberately not cryptographic.** ``encode(name:_:)`` produces
/// `"<name>.<base64url(JSON(value))>"` and ``decode(name:from:as:)`` reverses it, checking only that the
/// embedded name matches (a stand-in for the real MAC's name-binding). This lets tests exercise the
/// *shape* of encode/decode round-tripping deterministically; it is not a security primitive and never
/// signs. For real signing, use ``CookieManager``.
public final class MockCookieManaging: CookieManaging, @unchecked Sendable {
  /// A recorded ``encode(name:_:)`` invocation. `payload` is the JSON bytes of the encoded value, so a
  /// test can assert on exactly what was serialized without the double being generic over the value type.
  public struct EncodeCall: Sendable, Equatable {
    public let name: String
    public let payload: Data
  }

  /// A recorded ``decode(name:from:as:)`` invocation.
  public struct DecodeCall: Sendable, Equatable {
    public let name: String
    public let encoded: String
  }

  /// A recorded ``buildCookie(name:_:)`` invocation.
  public struct BuildCookieCall: Sendable, Equatable {
    public let name: String
    public let payload: Data
  }

  private struct State {
    var encodeCalls: [EncodeCall] = []
    var decodeCalls: [DecodeCall] = []
    var buildCookieCalls: [BuildCookieCall] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// The domain stamped onto cookies produced by ``buildCookie(name:_:)`` (real `HTTPCookie` construction
  /// requires one). Injectable so a test can assert the domain it expects.
  private let domain: String

  public var encodeCalls: [EncodeCall] { state.withLock { $0.encodeCalls } }
  public var decodeCalls: [DecodeCall] { state.withLock { $0.decodeCalls } }
  public var buildCookieCalls: [BuildCookieCall] { state.withLock { $0.buildCookieCalls } }

  public init(domain: String = "mock.local") {
    self.domain = domain
  }

  public func encode(name: String, _ value: some Encodable) throws(CookieError) -> String {
    let payload: Data
    do {
      payload = try JSONEncoder().encode(value)
    } catch {
      throw .serializationFailed
    }
    state.withLock { $0.encodeCalls.append(EncodeCall(name: name, payload: payload)) }
    return "\(name).\(Base64URL.encode(payload))"
  }

  public func decode<Value: Decodable>(
    name: String, from encoded: String, as _: Value.Type
  ) throws(CookieError) -> Value {
    state.withLock { $0.decodeCalls.append(DecodeCall(name: name, encoded: encoded)) }

    // Split on the first '.', mirroring the "<name>.<payload>" shape encode produces.
    guard let dot = encoded.firstIndex(of: ".") else { throw .malformedValue }
    let embeddedName = String(encoded[..<dot])
    let encodedPayload = String(encoded[encoded.index(after: dot)...])

    // Name-binding stand-in for the real MAC: a value encoded under one name won't decode under another.
    guard embeddedName == name else { throw .macInvalid }
    guard let payload = Base64URL.decode(encodedPayload) else { throw .malformedValue }

    do {
      return try JSONDecoder().decode(Value.self, from: payload)
    } catch {
      throw .deserializationFailed
    }
  }

  public func buildCookie(name: String, _ value: some Encodable) throws(CookieError) -> HTTPCookie {
    let payload: Data
    do {
      payload = try JSONEncoder().encode(value)
    } catch {
      throw .serializationFailed
    }
    state.withLock { $0.buildCookieCalls.append(BuildCookieCall(name: name, payload: payload)) }

    guard
      let cookie = HTTPCookie(properties: [
        .name: name,
        .value: "\(name).\(Base64URL.encode(payload))",
        .path: "/",
        .domain: domain,
      ])
    else {
      throw .cookieConstructionFailed
    }
    return cookie
  }
}
