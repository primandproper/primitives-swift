/// Configuration for the LaunchDarkly backend, ported from platform-go's `launchdarkly.Config`
/// (`featureflags/launchdarkly/config.go`).
///
/// Go's struct also carries a `CircuitBreakerConfig circuitbreakingcfg.Config` field, but that field is
/// only ever consumed by `launchdarkly.NewFeatureFlagManager` when wiring the real client, and this
/// platform never builds one, see ``FeatureFlagsConfig/makeFeatureFlagManager()``. Dropping it keeps this
/// module dependency-free without breaking decode: `Codable` ignores JSON keys it doesn't recognize, so a
/// Go-authored payload's `circuitBreakerConfig` object is simply skipped rather than rejected.
///
/// **Durations on the wire.** Go's `time.Duration` is an `int64` nanosecond count and marshals to JSON as
/// a bare integer. To round-trip byte-for-byte with a Go peer, ``initTimeout`` encodes as an integer
/// nanosecond count too, converted via `Duration.wholeNanoseconds` on the way out and rebuilt with
/// `.nanoseconds(_:)` on the way in (the same convention ``Retry``'s `RetryConfig` uses).
public struct LaunchDarklyConfig: Codable, Sendable, Equatable {
  /// The LaunchDarkly SDK key. Required for a real client; unused since this platform never builds one.
  public var sdkKey: String
  /// The client initialization timeout. Zero mirrors Go's zero-valued `time.Duration`.
  public var initTimeout: Duration

  public init(sdkKey: String = "", initTimeout: Duration = .zero) {
    self.sdkKey = sdkKey
    self.initTimeout = initTimeout
  }

  private enum CodingKeys: String, CodingKey {
    case sdkKey
    case initTimeout
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sdkKey = try c.decodeIfPresent(String.self, forKey: .sdkKey) ?? ""
    initTimeout = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .initTimeout) ?? 0)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(sdkKey, forKey: .sdkKey)
    try c.encode(initTimeout.wholeNanoseconds, forKey: .initTimeout)
  }
}

extension Duration {
  /// This duration as a whole count of nanoseconds, truncating any finer (sub-nanosecond) resolution,
  /// the unit Go's `time.Duration` uses natively. Mirrors ``Retry``'s internal helper of the same name;
  /// kept `internal` here too so importing both modules never raises an ambiguity.
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }
}
