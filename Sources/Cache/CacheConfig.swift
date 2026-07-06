import CircuitBreaking
import DurationWire
import Encoding
import Foundation
import Observability

/// Configuration for the cache, ported from platform-go's `cachecfg.Config` (`cache/config/config.go`).
///
/// **What's dropped.** Go's `Config` carried a `*redis.Config` and provided a Redis-backed cache. This
/// port **drops Redis entirely** (no server backend on iOS) but preserves the *provider seam*: the
/// embedded ``circuitBreaker`` config is retained per the settled rule ("remote-backed modules embed a
/// `CircuitBreakerConfig`") so a future remote/Redis adapter can wrap in without a wire-format change,
/// and an unknown provider string (including `"redis"`) resolves to ``CacheError/invalidProvider(_:)``
/// rather than silently degrading.
///
/// **Providers.** `""`/`"memory"` → ``InMemoryCache`` (the local default, like Go's `ProviderMemory`);
/// `"disk"` → ``DiskCache`` (this port's persistent local layer, filling Redis's slot without a network).
///
/// **Lenient decode.** `init(from:)` fills every missing key with its Go zero value, so `{}` and partial
/// JSON decode successfully (the settled Config rule). `expiry` is an integer **nanosecond** count on the
/// wire, matching Go's `time.Duration` JSON shape and ``FeatureFlags``' `LaunchDarklyConfig`.
public struct CacheConfig: Codable, Sendable, Equatable {
  /// Backend selector. Raw string (not a closed enum) so an unrecognized Go-authored value — e.g.
  /// `"redis"` — decodes rather than throwing; resolution happens in ``makeCache(pillars:encoder:)``.
  public var provider: String
  /// Per-entry TTL. Zero (Go's zero `Duration`) resolves to one hour at provide time, matching Go's
  /// `expiry <= 0 → time.Hour` fallback.
  public var expiry: Duration
  /// LRU capacity for the memory provider. `0` (default) is unbounded. A port addition (Go's map was
  /// uncapped); ignored by the disk provider.
  public var maxEntries: Int
  /// Directory for the disk provider. `nil` uses the app's caches directory under a `platform-swift-cache`
  /// subfolder. Ignored by the memory provider.
  public var directory: String?
  /// Circuit-breaker config for the future remote provider. Unused by the local providers; carried per
  /// the settled remote-config rule so a Redis adapter can wrap in without a wire change.
  public var circuitBreaker: CircuitBreakerConfig

  public init(
    provider: String = "",
    expiry: Duration = .zero,
    maxEntries: Int = 0,
    directory: String? = nil,
    circuitBreaker: CircuitBreakerConfig = .init()
  ) {
    self.provider = provider
    self.expiry = expiry
    self.maxEntries = maxEntries
    self.directory = directory
    self.circuitBreaker = circuitBreaker
  }

  /// The expiry to actually use: Go applies `time.Hour` when the configured value is non-positive.
  public var resolvedExpiry: Duration {
    expiry <= .zero ? .seconds(3600) : expiry
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case expiry
    case maxEntries
    case directory
    case circuitBreaker = "circuitBreakerConfig"
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    expiry = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .expiry) ?? 0)
    maxEntries = try c.decodeIfPresent(Int.self, forKey: .maxEntries) ?? 0
    directory = try c.decodeIfPresent(String.self, forKey: .directory)
    circuitBreaker =
      try c.decodeIfPresent(CircuitBreakerConfig.self, forKey: .circuitBreaker) ?? .init()
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(provider, forKey: .provider)
    try c.encode(expiry.wholeNanoseconds, forKey: .expiry)
    try c.encode(maxEntries, forKey: .maxEntries)
    try c.encodeIfPresent(directory, forKey: .directory)
    try c.encode(circuitBreaker, forKey: .circuitBreaker)
  }

  /// Builds the configured cache — the port of Go's `ProvideCache`.
  ///
  /// `""`/`"memory"` → ``InMemoryCache``; `"disk"` → ``DiskCache`` (rooted at ``directory`` or the app
  /// caches dir). Any other value (e.g. `"redis"`) throws ``CacheError/invalidProvider(_:)``, matching
  /// Go's `default` error branch.
  ///
  /// - Parameters:
  ///   - pillars: observability pillars threaded into the built cache.
  ///   - encoder: codec the disk provider encodes values through. Defaults to ``Encoding/JSONClientEncoder``.
  public func makeCache<Value: Codable & Sendable>(
    pillars: Pillars,
    encoder: any ClientEncoder = JSONClientEncoder()
  ) throws -> any BatchCache<Value> {
    switch provider.trimmingCharacters(in: .whitespaces).lowercased() {
    case "", "memory":
      return InMemoryCache<Value>(
        expiry: resolvedExpiry, maxEntries: maxEntries, pillars: pillars)
    case "disk":
      let dir: URL
      if let directory, !directory.isEmpty {
        dir = URL(fileURLWithPath: directory, isDirectory: true)
      } else {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let base = caches.first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        dir = base.appendingPathComponent("platform-swift-cache", isDirectory: true)
      }
      return try DiskCache<Value>(
        directory: dir, expiry: resolvedExpiry, pillars: pillars, encoder: encoder)
    default:
      throw CacheError.invalidProvider(provider)
    }
  }
}

extension Duration {
  /// This duration as a fractional number of seconds — the unit `Date`/`TimeInterval` arithmetic uses.
  var timeIntervalValue: TimeInterval {
    let (seconds, attoseconds) = components
    return Double(seconds) + Double(attoseconds) / 1e18
  }
}
