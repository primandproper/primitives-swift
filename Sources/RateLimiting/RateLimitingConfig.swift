import Foundation
import Observability

/// Configures rate limiting, ported from platform-go's `ratelimitingcfg.Config`
/// (`ratelimiting/config/config.go`), including its `EnsureDefaults` and `ProvideRateLimiter`.
///
/// Go's struct also carries a `Redis redisrl.Config` field selected by `Provider == "redis"`. Per the
/// port's native-seam rule (drop server/cloud backends, keep the protocol seam), the Redis-backed
/// sliding-window limiter is dropped entirely along with its sub-config: an unrecognized
/// ``provider`` — including `"redis"`, now that nothing implements it — throws
/// ``RateLimitingError/unknownProvider(_:)`` from ``provideRateLimiter(pillars:)``, same as any other
/// unrecognized string. A Go-authored payload's `redis` object still decodes fine (`Codable` ignores
/// unrecognized keys); it's simply never consulted.
///
/// ``provider`` stays a raw `String` rather than an enum — the same move ``FeatureFlagsConfig`` makes
/// for its `provider` field: Go treats `""` (unset) as a valid, meaningful value (falls through to
/// no-op) distinct from a genuinely *invalid* one, and ``validate()`` vs. ``provideRateLimiter(pillars:)``
/// apply two different degrees of leniency to it, matching Go exactly.
public struct RateLimitingConfig: Codable, Sendable, Equatable {
  /// Selects the no-op limiter (always allows). Matches Go's `ratelimitingcfg.ProviderNoop`.
  public static let providerNoop = "noop"
  /// Selects ``TokenBucketRateLimiter``. Matches Go's `ratelimitingcfg.ProviderMemory`.
  public static let providerMemory = "memory"

  static let defaultRequestsPerSecond = 10.0
  static let defaultBurstSize = 20

  /// The selected backend: `""`/`"noop"` for ``NoopRateLimiter``, `"memory"` for
  /// ``TokenBucketRateLimiter``, anything else is invalid.
  public var provider: String
  /// Steady-state refill rate, in tokens/second. Zero (including the un-decoded default) becomes `10.0`
  /// via ``ensureDefaults()``, matching Go's `defaultRequestsPerSec`.
  public var requestsPerSecond: Double
  /// Bucket capacity / maximum burst. Zero becomes `20` via ``ensureDefaults()``, matching Go's
  /// `defaultBurstSize`.
  public var burstSize: Int

  public init(
    provider: String = "", requestsPerSecond: Double = 0, burstSize: Int = 0
  ) {
    self.provider = provider
    self.requestsPerSecond = requestsPerSecond
    self.burstSize = burstSize
  }

  /// Fills unset (zero) fields with Go's defaults. Mirrors `Config.EnsureDefaults`.
  public mutating func ensureDefaults() {
    if requestsPerSecond == 0 {
      requestsPerSecond = Self.defaultRequestsPerSecond
    }
    if burstSize == 0 {
      burstSize = Self.defaultBurstSize
    }
  }

  /// A copy with ``ensureDefaults()`` applied.
  public func ensuringDefaults() -> RateLimitingConfig {
    var copy = self
    copy.ensureDefaults()
    return copy
  }

  /// Validates the config, mirroring Go's `ValidateWithContext` (`requestsPerSecond >= 0`,
  /// `burstSize >= 0`). Unlike ``provideRateLimiter(pillars:)``, this doesn't care about ``provider`` at
  /// all — Go's equivalent check never validated it either.
  /// - Throws: ``RateLimitingError/invalidRequestsPerSecond(_:)`` or
  ///   ``RateLimitingError/invalidBurstSize(_:)``.
  public func validate() throws {
    if requestsPerSecond < 0 {
      throw RateLimitingError.invalidRequestsPerSecond(requestsPerSecond)
    }
    if burstSize < 0 {
      throw RateLimitingError.invalidBurstSize(burstSize)
    }
  }

  /// Builds a live ``RateLimiter`` from this config — the port of Go's `Config.ProvideRateLimiter`.
  ///
  /// Like Go, this does **not** call ``validate()`` first: an empty ``provider`` resolves to
  /// ``NoopRateLimiter`` without error regardless of ``requestsPerSecond``/``burstSize``, matching the
  /// `default`-adjacent `"", ProviderNoop` case of Go's `switch`. Defaults are applied via
  /// ``ensureDefaults()`` first, exactly as Go's `ProvideRateLimiter` calls `cfg.EnsureDefaults()` before
  /// its `switch`.
  /// - Throws: ``RateLimitingError/unknownProvider(_:)`` for anything other than `""`, `"noop"`, or
  ///   `"memory"` — matching Go's `errors.Newf("unknown rate limiter provider: %q", cfg.Provider)`.
  public func provideRateLimiter(pillars: Pillars = .noop) throws -> any RateLimiter {
    var cfg = self
    cfg.ensureDefaults()

    switch cfg.provider.trimmingCharacters(in: .whitespaces).lowercased() {
    case "", Self.providerNoop:
      return NoopRateLimiter()
    case Self.providerMemory:
      return TokenBucketRateLimiter(
        requestsPerSecond: cfg.requestsPerSecond, burstSize: cfg.burstSize, pillars: pillars)
    default:
      throw RateLimitingError.unknownProvider(cfg.provider)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case requestsPerSecond
    case burstSize
  }

  /// Lenient decode: missing fields decode to Go's zero values so ``ensureDefaults()`` can fill them,
  /// matching how a partial JSON object unmarshals into a Go struct.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    requestsPerSecond = try c.decodeIfPresent(Double.self, forKey: .requestsPerSecond) ?? 0
    burstSize = try c.decodeIfPresent(Int.self, forKey: .burstSize) ?? 0
  }
}
