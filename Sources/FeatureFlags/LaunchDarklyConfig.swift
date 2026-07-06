import DurationWire

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
  /// The LaunchDarkly **server-side SDK key**, carried verbatim from the Go config.
  ///
  /// **Do not wire this into a mobile client as-is.** LaunchDarkly draws a hard line between credential
  /// types: a *server* SDK key (this field, `sdk-*`) authorizes the server-side SDK to stream the full
  /// ruleset and evaluate flags locally, and must **never** ship inside a mobile app — anyone can extract
  /// it and read every flag/segment. Mobile devices instead use a *mobile key* (`mob-*`), which only
  /// authorizes fetching already-evaluated flag values for a single context from LaunchDarkly's client
  /// endpoints. Because this port carries only the server key, ``FeatureFlagsConfig/makeFeatureFlagManager()``
  /// deliberately throws for LaunchDarkly rather than misusing it; a real iOS LaunchDarkly backend must
  /// first add a distinct mobile-key field and target the client-side (`/msdk`/`/meval`) endpoints.
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
