import Foundation

/// The resolved SameSite mode, ported from the `SameSiteLax`/`SameSiteStrict`/`SameSiteNone` string
/// constants in platform-go's `cookies` package.
///
/// Go stores `Config.SameSite` as a raw, case-insensitive string (empty defaults to Lax) and maps it
/// to `http.SameSite` via `sameSiteMode`. ``CookieConfig`` keeps the raw string for wire fidelity and
/// cross-field validation (`none` requires `secureOnly`), then resolves it into this closed enum via
/// ``CookieConfig/resolvedSameSite``. The raw values match Go's constants so a config payload
/// round-trips.
public enum SameSitePolicy: String, Codable, Sendable, CaseIterable {
  case lax
  case strict
  /// Foundation's `HTTPCookie` has no "None" representation — it is expressed by the *absence* of a
  /// SameSite policy. ``CookieManager/buildCookie(name:_:)`` therefore omits the attribute for this case.
  case none
}

/// Configuration for the cookie ``CookieManager``, ported from platform-go's `cookies.Config`.
///
/// Go tags each field with `env:` (read from the environment) and `json:`. Per the settled port
/// architecture, iOS apps don't configure from the environment, so only the JSON contract survives:
/// the keys match Go's (`domain`, `cookieName`, `base64EncodedHashKey`, `base64EncodedBlockKey`,
/// `sameSite`, `lifetime`, `secureOnly`).
///
/// **Durations on the wire.** Like ``Retry``'s `RetryConfig`, ``lifetime`` mirrors Go's `time.Duration`,
/// which marshals to JSON as a bare integer of **nanoseconds**; it is converted via `wholeNanoseconds`
/// on the way out and rebuilt with `.nanoseconds(_:)` on the way in so it round-trips byte-for-byte
/// with a Go peer.
///
/// **Keys.** ``base64EncodedHashKey`` / ``base64EncodedBlockKey`` are **standard** (not URL-safe)
/// base64, matching Go's `base64.StdEncoding.DecodeString`. Validation only checks they are non-empty;
/// their base64 validity is enforced when the ``CookieManager`` is built (mirroring Go, which decodes
/// the keys in `NewCookieManager`, not in `Validate`).
public struct CookieConfig: Codable, Sendable, Equatable {
  public var domain: String
  public var cookieName: String
  public var base64EncodedHashKey: String
  public var base64EncodedBlockKey: String
  /// Raw, case-insensitive SameSite string (empty → Lax); resolved by ``resolvedSameSite``.
  public var sameSite: String
  /// Cookie lifetime; zero means "unset" (no expiry bound). When non-zero, must be ≥ 5 minutes.
  public var lifetime: Duration
  public var secureOnly: Bool

  /// Minimum non-zero lifetime, mirroring Go's `minCookieLifetime = 5 * time.Minute`.
  public static let minLifetime: Duration = .seconds(300)

  public init(
    domain: String = "",
    cookieName: String = "",
    base64EncodedHashKey: String = "",
    base64EncodedBlockKey: String = "",
    sameSite: String = "",
    lifetime: Duration = .zero,
    secureOnly: Bool = false
  ) {
    self.domain = domain
    self.cookieName = cookieName
    self.base64EncodedHashKey = base64EncodedHashKey
    self.base64EncodedBlockKey = base64EncodedBlockKey
    self.sameSite = sameSite
    self.lifetime = lifetime
    self.secureOnly = secureOnly
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`.
  ///
  /// The rules are faithful to ozzo-validation's behavior: `cookieName`, the hash key, and the block
  /// key are *required* (non-empty); `lifetime` is checked against the 5-minute minimum only when
  /// non-zero (ozzo skips empty values for non-`Required` rules); and `sameSite` accepts empty / `lax`
  /// / `strict` case-insensitively, permits `none` only with `secureOnly` (browsers silently drop a
  /// non-Secure `SameSite=None` cookie), and rejects anything else.
  public func validate() throws(CookieError) {
    guard !cookieName.isEmpty else {
      throw .invalidConfiguration("cookieName is required")
    }
    guard !base64EncodedHashKey.isEmpty else {
      throw .invalidConfiguration("base64EncodedHashKey is required")
    }
    guard !base64EncodedBlockKey.isEmpty else {
      throw .invalidConfiguration("base64EncodedBlockKey is required")
    }
    if lifetime != .zero && lifetime < Self.minLifetime {
      throw .invalidConfiguration("lifetime must be at least 5 minutes when set")
    }

    switch sameSite.lowercased() {
    case "", SameSitePolicy.lax.rawValue, SameSitePolicy.strict.rawValue:
      break
    case SameSitePolicy.none.rawValue:
      if !secureOnly {
        throw .invalidConfiguration("SameSite=none requires secureOnly")
      }
    default:
      throw .invalidConfiguration("unsupported SameSite value \"\(sameSite)\"")
    }
  }

  /// Resolves ``sameSite`` to a ``SameSitePolicy``, defaulting to `.lax` for the empty (or any
  /// otherwise-unexpected) value — mirroring Go's `sameSiteMode`. Validation rejects unsupported
  /// values before they reach here.
  public var resolvedSameSite: SameSitePolicy {
    switch sameSite.lowercased() {
    case SameSitePolicy.strict.rawValue: return .strict
    case SameSitePolicy.none.rawValue: return .none
    default: return .lax
    }
  }

  private enum CodingKeys: String, CodingKey {
    case domain
    case cookieName
    case base64EncodedHashKey
    case base64EncodedBlockKey
    case sameSite
    case lifetime
    case secureOnly
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // Missing fields decode to Go's zero values, matching how a partial JSON object unmarshals into a
    // Go struct.
    domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
    cookieName = try c.decodeIfPresent(String.self, forKey: .cookieName) ?? ""
    base64EncodedHashKey = try c.decodeIfPresent(String.self, forKey: .base64EncodedHashKey) ?? ""
    base64EncodedBlockKey = try c.decodeIfPresent(String.self, forKey: .base64EncodedBlockKey) ?? ""
    sameSite = try c.decodeIfPresent(String.self, forKey: .sameSite) ?? ""
    lifetime = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .lifetime) ?? 0)
    secureOnly = try c.decodeIfPresent(Bool.self, forKey: .secureOnly) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(domain, forKey: .domain)
    try c.encode(cookieName, forKey: .cookieName)
    try c.encode(base64EncodedHashKey, forKey: .base64EncodedHashKey)
    try c.encode(base64EncodedBlockKey, forKey: .base64EncodedBlockKey)
    try c.encode(sameSite, forKey: .sameSite)
    try c.encode(lifetime.wholeNanoseconds, forKey: .lifetime)
    try c.encode(secureOnly, forKey: .secureOnly)
  }
}

extension Duration {
  /// This duration as a whole count of nanoseconds — the unit Go's `time.Duration` marshals to JSON.
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }

  /// This duration as a whole count of seconds, truncating any finer resolution — used for the
  /// signed-cookie `MaxAge` bound and the `HTTPCookie` expiry, matching Go's `int(lifetime.Seconds())`.
  var wholeSeconds: Int64 {
    components.seconds
  }
}
