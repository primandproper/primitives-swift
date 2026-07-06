import Foundation

/// Configuration for an ``HTTPClient``, ported from platform-go's `httpclient.Config`.
///
/// Go tags each field with `env:` (read from the environment) and `json:`. Per the settled port
/// architecture, iOS apps don't configure from the environment, so only the JSON contract survives:
/// this is a plain `Codable` struct whose keys match Go's (`timeout`, `maxIdleConns`,
/// `maxIdleConnsPerHost`, `enableTracing`).
///
/// **Durations on the wire.** Go's `time.Duration` is an `int64` nanosecond count and marshals to JSON
/// as a bare integer of nanoseconds. To round-trip byte-for-byte with a Go peer, ``timeout`` encodes as
/// **integer nanoseconds** here too — the Swift `Duration` is converted on the way out and rebuilt with
/// `.nanoseconds(_:)` on the way in, exactly as the ported `RetryConfig` does.
///
/// **Idle-connection tuning.** Go configures a fully custom `http.Transport` with separate
/// `MaxIdleConns` (process-wide) and `MaxIdleConnsPerHost` caps. `URLSession` exposes only the
/// per-host cap (`httpMaximumConnectionsPerHost`), so ``maxIdleConnsPerHost`` maps onto it and
/// ``maxIdleConns`` is carried for wire-compat / documentation only — there is no `URLSession` knob
/// for a global idle-connection ceiling. See ``buildSessionConfiguration()``.
public struct HTTPClientConfig: Codable, Sendable, Equatable {
  /// Request timeout. Maps to `URLSessionConfiguration.timeoutIntervalForRequest`.
  ///
  /// **Semantics differ from Go's.** `timeoutIntervalForRequest` is URLSession's *inter-byte idle*
  /// timeout — the clock resets whenever new data arrives, so it bounds the gap *between* bytes, not the
  /// total request. Go's `http.Client.Timeout`, by contrast, is a hard ceiling on the *whole* exchange
  /// (dial + write + read). The nearest total-time bound in URLSession is `timeoutIntervalForResource`,
  /// which ``buildSessionConfiguration()`` derives from this value (3×). So a request that dribbles bytes
  /// forever is cut off by the resource timeout, not this one.
  public var timeout: Duration
  /// Process-wide idle-connection cap in Go. **No `URLSession` analogue** — retained for wire-compat.
  public var maxIdleConns: Int
  /// Per-host idle-connection cap. Maps to `URLSessionConfiguration.httpMaximumConnectionsPerHost`.
  public var maxIdleConnsPerHost: Int
  /// In Go this selected the `otelhttp` transport. In Swift, request instrumentation is a wrapper
  /// concern driven by the injected ``Observability/Observer``; when this is `false`, the
  /// ``HTTPClient/init(config:pillars:retryPolicy:circuitBreaker:)`` convenience swaps in a no-op
  /// tracer so spans are suppressed while logging/metrics stay on. See that initializer.
  public var enableTracing: Bool
  /// Whether URLSession should *wait* for connectivity instead of failing immediately when the network is
  /// unreachable. Maps to `URLSessionConfiguration.waitsForConnectivity`.
  ///
  /// **Defaults to `false`** to match Go's `http.Client`, which has no wait-for-connectivity behavior — an
  /// offline request fails fast rather than parking until a route appears. This is also URLSession's own
  /// default, so the conservative choice keeps parity on both sides. Set `true` for apps that prefer to
  /// let a request ride out a transient connectivity gap (bounded by `timeoutIntervalForResource`).
  public var waitsForConnectivity: Bool

  static let defaultTimeout: Duration = .seconds(10)
  static let defaultMaxIdleConns = 100
  static let defaultMaxIdleConnsPerHost = 100

  public init(
    timeout: Duration = .zero,
    maxIdleConns: Int = 0,
    maxIdleConnsPerHost: Int = 0,
    enableTracing: Bool = false,
    waitsForConnectivity: Bool = false
  ) {
    self.timeout = timeout
    self.maxIdleConns = maxIdleConns
    self.maxIdleConnsPerHost = maxIdleConnsPerHost
    self.enableTracing = enableTracing
    self.waitsForConnectivity = waitsForConnectivity
  }

  /// Fills defaults for zero fields, mirroring Go's `Config.EnsureDefaults`.
  public mutating func ensureDefaults() {
    if timeout <= .zero {
      timeout = Self.defaultTimeout
    }
    if maxIdleConns == 0 {
      maxIdleConns = Self.defaultMaxIdleConns
    }
    if maxIdleConnsPerHost == 0 {
      maxIdleConnsPerHost = Self.defaultMaxIdleConnsPerHost
    }
  }

  /// A copy with ``ensureDefaults()`` applied — handy where a mutating call is awkward.
  public func ensuringDefaults() -> HTTPClientConfig {
    var copy = self
    copy.ensureDefaults()
    return copy
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`. Unlike Go's `ozzo-validation`
  /// (which returns a rich field-error map), this throws a single ``HTTPClientError/invalidConfig(_:)``
  /// on the first violation — Swift callers inspect the message, and the field checks are the same:
  /// timeout must be at least a millisecond, both connection caps at least one.
  public func validate() throws {
    if timeout < .milliseconds(1) {
      throw HTTPClientError.invalidConfig("timeout must be at least 1ms")
    }
    if maxIdleConns < 1 {
      throw HTTPClientError.invalidConfig("maxIdleConns must be at least 1")
    }
    if maxIdleConnsPerHost < 1 {
      throw HTTPClientError.invalidConfig("maxIdleConnsPerHost must be at least 1")
    }
  }

  /// Builds the `URLSessionConfiguration` this config describes, the analogue of Go's
  /// `Config.BuildClient` assembling an `http.Transport`. Defaults are applied first so a zero-valued
  /// config never yields a pathological session.
  public func buildSessionConfiguration() -> URLSessionConfiguration {
    let cfg = ensuringDefaults()
    let sessionConfig = URLSessionConfiguration.default
    sessionConfig.timeoutIntervalForRequest = cfg.timeout.timeInterval
    // Go's ExpectContinueTimeout/IdleConnTimeout are derived from the request timeout; the closest
    // URLSession knob is the resource timeout, which we scale the same way (3× the request timeout).
    sessionConfig.timeoutIntervalForResource = (cfg.timeout * 3).timeInterval
    sessionConfig.httpMaximumConnectionsPerHost = cfg.maxIdleConnsPerHost
    sessionConfig.waitsForConnectivity = cfg.waitsForConnectivity
    return sessionConfig
  }

  /// Builds a `URLSession` from this config — the direct analogue of Go's `Config.BuildClient`.
  public func buildSession() -> URLSession {
    URLSession(configuration: buildSessionConfiguration())
  }

  // MARK: - Codable (nanosecond duration contract)

  private enum CodingKeys: String, CodingKey {
    case timeout
    case maxIdleConns
    case maxIdleConnsPerHost
    case enableTracing
    case waitsForConnectivity
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // Missing fields decode to Go's zero values so ``ensureDefaults()`` can fill them, matching how a
    // partial JSON object unmarshals into a Go struct.
    timeout = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .timeout) ?? 0)
    maxIdleConns = try c.decodeIfPresent(Int.self, forKey: .maxIdleConns) ?? 0
    maxIdleConnsPerHost = try c.decodeIfPresent(Int.self, forKey: .maxIdleConnsPerHost) ?? 0
    enableTracing = try c.decodeIfPresent(Bool.self, forKey: .enableTracing) ?? false
    waitsForConnectivity = try c.decodeIfPresent(Bool.self, forKey: .waitsForConnectivity) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(timeout.wholeNanoseconds, forKey: .timeout)
    try c.encode(maxIdleConns, forKey: .maxIdleConns)
    try c.encode(maxIdleConnsPerHost, forKey: .maxIdleConnsPerHost)
    try c.encode(enableTracing, forKey: .enableTracing)
    try c.encode(waitsForConnectivity, forKey: .waitsForConnectivity)
  }
}

extension Duration {
  /// This duration as a whole count of nanoseconds — the unit Go's `time.Duration` uses natively and
  /// marshals to JSON. Truncates any sub-nanosecond resolution.
  ///
  /// `Retry` defines an identical helper for its own config; it lives `internal` there, so this module
  /// carries its own copy rather than reaching across a target boundary for a two-line conversion.
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }

  /// This duration as `TimeInterval` (seconds), the unit `URLSessionConfiguration` timeouts expect.
  var timeInterval: TimeInterval {
    let (seconds, attoseconds) = components
    return Double(seconds) + Double(attoseconds) / 1e18
  }
}
