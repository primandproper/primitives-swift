import CryptoKit
import Foundation

/// Signs, verifies, and builds secure session cookies, ported from platform-go's `cookies.Manager`
/// (which wraps `gorilla/securecookie`).
///
/// ## What the Go Manager does, and what carries over
///
/// The Go `Manager` `Encode`s a value by: serializing it (gob), *optionally encrypting* it (AES in
/// CTR mode, random IV prepended), base64url-encoding, then signing `name|timestamp|payload` with
/// **HMAC-SHA256** and wrapping the whole envelope in base64url. `Decode` reverses this — verifying
/// the MAC (constant-time), enforcing the timestamp against the configured lifetime, then decrypting
/// and deserializing. `BuildCookie` stamps the encoded value with the configured security attributes.
///
/// This port reproduces the **HMAC-SHA256 signing envelope faithfully** with CryptoKit
/// (`HMAC<SHA256>`), including the exact byte layout `base64url( "date|" ‖ base64url(payload) ‖ "|" ‖
/// mac )` and the name-binding that makes a value valid only under the cookie name it was signed for.
/// That envelope is the security-critical core and is wire-compatible with a Go `securecookie`
/// configured for a hash key with **no block key and a JSON serializer**.
///
/// ## Deferred / honestly-incompatible pieces
///
/// Two parts of the Go scheme have **no clean CryptoKit analogue** and are not reproduced:
///
///   * **AES-CTR encryption** (the block-key path). CryptoKit exposes AES-GCM, not CTR-mode streaming;
///     reproducing `securecookie`'s `cipher.NewCTR` byte layout would mean dropping to CommonCrypto.
///     This port signs but does **not encrypt** the payload. The block key is still validated (for
///     config parity with Go, which requires it) but otherwise unused — reserved for a future
///     CommonCrypto-backed CTR path.
///   * **gob serialization.** Go's default serializer is `encoding/gob`, a Go-specific format with no
///     Swift equivalent. This port uses JSON (`Codable`), matching `securecookie`'s alternative
///     `JSONEncoder`. End-to-end interop with a Go peer therefore additionally requires the Go side to
///     select a JSON serializer and matching payload bytes.
///
/// The net: the **signature scheme** is faithful and verifiable; the **payload confidentiality and
/// serialization format** are not byte-compatible with the platform-go default configuration. For a
/// pure iOS client this is usually moot — see the note on `HTTPCookieStorage` below.
///
/// ## What `HTTPCookieStorage` already subsumes
///
/// A native iOS client that merely *stores and resends* server-set cookies needs none of this: it
/// treats each cookie value as opaque and lets `HTTPCookieStorage` / `URLSession` persist and attach
/// them automatically. The signing/verification here is only relevant when the app must itself
/// *mint or validate* signed cookie values (e.g. a client-side session token), and the
/// browser-enforcement attributes (`HttpOnly`, `SameSite`) that ``buildCookie(name:_:)`` sets have
/// limited meaning for a non-browser client.
///
/// ## Observability
///
/// Go threads an `observability.Observer` through every method. Like ``Cryptography``, this port keeps
/// the primitive decoupled from the o11y graph: a crypto operation shouldn't drag in observability or
/// risk logging value lengths. Failures surface as thrown ``CookieError`` values a caller traces at
/// its own layer.
public struct CookieManager: Sendable {
  private let config: CookieConfig
  private let hashKey: SymmetricKey
  private let sameSite: SameSitePolicy
  /// Current Unix time in seconds (UTC). Injectable for deterministic timestamp/expiry tests;
  /// defaults to the wall clock. Mirrors `securecookie`'s overridable `timeFunc`.
  private let now: @Sendable () -> Int64

  /// Builds a manager from a validated config, mirroring Go's `NewCookieManager`.
  ///
  /// - Throws: ``CookieError/invalidConfiguration(_:)`` if the config is invalid,
  ///   ``CookieError/invalidHashKey`` / ``CookieError/invalidBlockKey`` if a key is not valid
  ///   standard base64.
  public init(config: CookieConfig) throws(CookieError) {
    try self.init(config: config, now: CookieManager.wallClockSeconds)
  }

  init(config: CookieConfig, now: @escaping @Sendable () -> Int64) throws(CookieError) {
    try config.validate()

    guard let hashKeyData = Data(base64Encoded: config.base64EncodedHashKey), !hashKeyData.isEmpty
    else {
      throw .invalidHashKey
    }
    // Validated for parity with Go (which requires and decodes it) even though the AES-CTR path it
    // feeds is deferred — see the type doc.
    guard Data(base64Encoded: config.base64EncodedBlockKey) != nil else {
      throw .invalidBlockKey
    }

    self.config = config
    self.hashKey = SymmetricKey(data: hashKeyData)
    self.sameSite = config.resolvedSameSite
    self.now = now
  }

  private static let wallClockSeconds: @Sendable () -> Int64 = {
    Int64(Date().timeIntervalSince1970)
  }

  /// securecookie's default decode `MaxAge` (`86400 * 30`), applied when no lifetime is configured so
  /// an unset lifetime still bounds the replay window. Mirrors Go's `NewCookieManager`, which leaves
  /// `securecookie`'s 30-day default in place and only overrides it when `Lifetime > 0`.
  static let defaultDecodeMaxAgeSeconds: Int64 = 86_400 * 30

  /// Serializes and signs `value`, returning the encoded cookie value. Wraps `securecookie.Encode`
  /// (signing only — see the type doc on the deferred encryption path).
  ///
  /// - Parameters:
  ///   - name: the cookie name, bound into the MAC — a value encoded under one name will not verify
  ///     under another.
  ///   - value: any `Encodable` payload (JSON-serialized).
  public func encode(name: String, _ value: some Encodable) throws(CookieError) -> String {
    let payload: Data
    do {
      payload = try JSONEncoder().encode(value)
    } catch {
      throw .serializationFailed
    }

    let encodedPayload = Base64URL.encode(payload)
    let timestamp = now()

    // MAC over "name|timestamp|encodedPayload", matching securecookie's createMac input.
    let macInput = Data("\(name)|\(timestamp)|\(encodedPayload)".utf8)
    let mac = HMAC<SHA256>.authenticationCode(for: macInput, using: hashKey)

    // Envelope bytes: "timestamp|encodedPayload|" ‖ rawMac, then base64url — the securecookie layout
    // with the leading "name|" sliced off.
    var envelope = Data("\(timestamp)|\(encodedPayload)|".utf8)
    envelope.append(contentsOf: mac)
    return Base64URL.encode(envelope)
  }

  /// Verifies and deserializes an encoded cookie value, returning the payload. Wraps
  /// `securecookie.Decode`.
  ///
  /// - Throws: ``CookieError/malformedValue`` for a structurally bad value, ``CookieError/macInvalid``
  ///   for a failed signature (tampering, wrong key, or wrong `name`), ``CookieError/timestampInvalid``
  ///   for an unparseable timestamp, ``CookieError/expired`` if older than the configured lifetime
  ///   (or securecookie's 30-day default when no lifetime is set), or
  ///   ``CookieError/deserializationFailed`` if the payload doesn't decode into `Value`.
  public func decode<Value: Decodable>(
    name: String, from encoded: String, as _: Value.Type = Value.self
  ) throws(CookieError) -> Value {
    guard let raw = Base64URL.decode(encoded) else {
      throw .malformedValue
    }

    // Split into exactly three parts on the first two '|' bytes; the trailing mac is raw HMAC bytes
    // and may itself contain 0x7C, so we must not split it (matching Go's bytes.SplitN(…, 3)).
    let pipe: UInt8 = 0x7C
    guard let firstPipe = raw.firstIndex(of: pipe) else { throw .malformedValue }
    let afterFirst = raw.index(after: firstPipe)
    guard let secondPipe = raw[afterFirst...].firstIndex(of: pipe) else { throw .malformedValue }

    let datePart = raw[..<firstPipe]
    let payloadPart = raw[afterFirst..<secondPipe]
    let macPart = raw[raw.index(after: secondPipe)...]

    // Recompute the MAC over "name|date|encodedPayload" and verify in constant time.
    var macInput = Data("\(name)|".utf8)
    macInput.append(contentsOf: datePart)
    macInput.append(pipe)
    macInput.append(contentsOf: payloadPart)
    guard
      HMAC<SHA256>.isValidAuthenticationCode(macPart, authenticating: macInput, using: hashKey)
    else {
      throw .macInvalid
    }

    guard let timestamp = Int64(String(decoding: datePart, as: UTF8.self)) else {
      throw .timestampInvalid
    }
    // securecookie always bounds the MAC-protected timestamp: its `maxAge` defaults to 30 days and
    // Go's `NewCookieManager` only overrides that default when `Lifetime > 0`. Fall back to the same
    // 30-day bound for an unset lifetime rather than leaving the replay window open.
    let configuredSeconds = config.lifetime.wholeSeconds
    let maxAge = configuredSeconds > 0 ? configuredSeconds : Self.defaultDecodeMaxAgeSeconds
    if timestamp < now() - maxAge {
      throw .expired
    }

    guard let payload = Base64URL.decode(String(decoding: payloadPart, as: UTF8.self)) else {
      throw .malformedValue
    }

    do {
      return try JSONDecoder().decode(Value.self, from: payload)
    } catch {
      throw .deserializationFailed
    }
  }

  /// Encodes `value` and returns a ready-to-store `HTTPCookie` carrying the configured security
  /// attributes, ported from Go's `BuildCookie`.
  ///
  /// Maps the Go `http.Cookie` fields onto `HTTPCookie`: `Path` = `/`, `Domain`, `Secure` from
  /// `secureOnly`, `SameSite`, and expiry from `lifetime`. Two platform notes:
  ///
  ///   * **Domain is required.** `HTTPCookie` cannot be built without a domain (or origin URL); Go's
  ///     `http.Cookie` treats an empty domain as "current host". An empty ``CookieConfig/domain``
  ///     therefore throws ``CookieError/missingDomain`` rather than silently producing a hostless cookie.
  ///   * **`HttpOnly` / `SameSite=None` are best-effort.** `HttpOnly` is set via the undocumented
  ///     property key and is a browser-JS-boundary concept with no meaning for a native client;
  ///     `SameSite=None` has no `HTTPCookie` representation and is expressed as the *absence* of a
  ///     policy. Neither is asserted by the tests for that reason.
  public func buildCookie(name: String, _ value: some Encodable) throws(CookieError) -> HTTPCookie {
    let encoded = try encode(name: name, value)

    guard !config.domain.isEmpty else {
      throw .missingDomain
    }

    var properties: [HTTPCookiePropertyKey: Any] = [
      .name: name,
      .value: encoded,
      .path: "/",
      .domain: config.domain,
    ]

    if config.secureOnly {
      properties[.secure] = "TRUE"
    }

    switch sameSite {
    case .lax:
      properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
    case .strict:
      properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
    case .none:
      break  // HTTPCookie has no "None" — represented by omitting the policy.
    }

    // HttpOnly is a non-negotiable default in Go. Best-effort here via the undocumented key.
    properties[HTTPCookiePropertyKey("HTTPOnly")] = "TRUE"

    if config.lifetime != .zero {
      let seconds = config.lifetime.wholeSeconds
      properties[.expires] = Date().addingTimeInterval(TimeInterval(seconds))
      properties[.maximumAge] = String(seconds)
    }

    guard let cookie = HTTPCookie(properties: properties) else {
      throw .cookieConstructionFailed
    }
    return cookie
  }
}
