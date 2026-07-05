/// Configuration for a retry policy, ported from platform-go's `retry.Config`.
///
/// Go tags each field with `env:` (read from the environment) and `json:`. Per the settled port
/// architecture, iOS apps don't configure from the environment, so only the JSON contract survives:
/// this is a plain `Codable` struct whose keys match Go's (`maxAttempts`, `initialDelay`, `maxDelay`,
/// `multiplier`, `useJitter`).
///
/// **Durations on the wire.** Go's `time.Duration` is an `int64` nanosecond count and marshals to JSON
/// as a bare integer of nanoseconds. To round-trip byte-for-byte with a Go peer, ``initialDelay`` and
/// ``maxDelay`` encode as **integer nanoseconds** here too — the Swift `Duration` is converted via
/// ``Swift/Duration/wholeNanoseconds`` on the way out and rebuilt with `.nanoseconds(_:)` on the way in.
///
/// Like Go's zero-valued `Config`, the memberwise defaults are all zero/`false`; call
/// ``ensureDefaults()`` (the constructor of ``ExponentialBackoffPolicy`` does this for you) to fill and
/// clamp them.
public struct RetryConfig: Codable, Sendable, Equatable {
  /// Maximum number of attempts (not retries) before giving up. Zero is filled by ``ensureDefaults()``.
  public var maxAttempts: UInt
  /// Delay before the second attempt; grows by ``multiplier`` each time, capped at ``maxDelay``.
  public var initialDelay: Duration
  /// Ceiling on the per-attempt backoff delay.
  public var maxDelay: Duration
  /// Factor the delay is multiplied by after each failed attempt. Values below 1 are clamped.
  public var multiplier: Double
  /// When true, each delay is randomized within `[delay/2, delay)` to avoid thundering-herd retries.
  public var useJitter: Bool

  static let defaultMaxAttempts: UInt = 3
  static let defaultInitialDelay: Duration = .milliseconds(100)
  static let defaultMaxDelay: Duration = .seconds(5)
  static let defaultMultiplier: Double = 2.0

  public init(
    maxAttempts: UInt = 0,
    initialDelay: Duration = .zero,
    maxDelay: Duration = .zero,
    multiplier: Double = 0,
    useJitter: Bool = false
  ) {
    self.maxAttempts = maxAttempts
    self.initialDelay = initialDelay
    self.maxDelay = maxDelay
    self.multiplier = multiplier
    self.useJitter = useJitter
  }

  /// Fills defaults for zero fields and clamps invalid ones, mirroring Go's `Config.EnsureDefaults`.
  ///
  /// It *clamps* rather than merely zero-checking: because the constructor returns no error to reject a
  /// nonsensical config, a negative delay or a `multiplier` below 1 (which would shrink the backoff)
  /// would otherwise produce a pathological policy. Such values are replaced with the defaults.
  public mutating func ensureDefaults() {
    if maxAttempts == 0 {
      maxAttempts = Self.defaultMaxAttempts
    }
    if initialDelay <= .zero {
      initialDelay = Self.defaultInitialDelay
    }
    if maxDelay <= .zero {
      maxDelay = Self.defaultMaxDelay
    }
    if multiplier < 1 {
      multiplier = Self.defaultMultiplier
    }
  }

  /// A copy with ``ensureDefaults()`` applied — handy where a mutating call is awkward.
  public func ensuringDefaults() -> RetryConfig {
    var copy = self
    copy.ensureDefaults()
    return copy
  }

  private enum CodingKeys: String, CodingKey {
    case maxAttempts
    case initialDelay
    case maxDelay
    case multiplier
    case useJitter
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // Missing fields decode to Go's zero values so ``ensureDefaults()`` can fill them, matching how a
    // partial JSON object unmarshals into a Go struct.
    maxAttempts = try c.decodeIfPresent(UInt.self, forKey: .maxAttempts) ?? 0
    initialDelay = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .initialDelay) ?? 0)
    maxDelay = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .maxDelay) ?? 0)
    multiplier = try c.decodeIfPresent(Double.self, forKey: .multiplier) ?? 0
    useJitter = try c.decodeIfPresent(Bool.self, forKey: .useJitter) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(maxAttempts, forKey: .maxAttempts)
    try c.encode(initialDelay.wholeNanoseconds, forKey: .initialDelay)
    try c.encode(maxDelay.wholeNanoseconds, forKey: .maxDelay)
    try c.encode(multiplier, forKey: .multiplier)
    try c.encode(useJitter, forKey: .useJitter)
  }
}

extension Duration {
  /// This duration as a whole count of nanoseconds, truncating any finer (sub-nanosecond) resolution —
  /// the unit Go's `time.Duration` uses natively.
  ///
  /// Used both for the JSON contract (Go marshals durations as integer nanoseconds) and for the backoff
  /// math in ``ExponentialBackoffPolicy``, which — like Go — computes jitter and scaling in `int64`
  /// nanoseconds. This is why a sub-2ns delay halves to zero and the jitter step is skipped: the
  /// nanosecond truncation here reproduces Go's `int64(delay)/2 == 0` guard exactly.
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }
}
