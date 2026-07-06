import Foundation

/// Configures ``DiskSpaceChecker``, decoded leniently like every other config in this port.
public struct DiskSpaceCheckerConfig: Codable, Sendable, Equatable {
  public var minimumFreeBytes: Int64

  public init(minimumFreeBytes: Int64 = DiskSpaceChecker.defaultMinimumFreeBytes) {
    self.minimumFreeBytes = minimumFreeBytes
  }

  private enum CodingKeys: String, CodingKey {
    case minimumFreeBytes
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    minimumFreeBytes =
      try c.decodeIfPresent(Int64.self, forKey: .minimumFreeBytes)
      ?? DiskSpaceChecker.defaultMinimumFreeBytes
  }
}

/// The top-level health check configuration.
///
/// platform-go's `healthcheck` package carries no `Config` type of its own — the registry, its default
/// timeout, and every checker are wired directly in application code. This port adds one anyway, per Wave
/// 5's spec, so an app can decode its check timeout and disk-space threshold from the same JSON/plist tree
/// as its other pillars rather than hardcoding them: a deliberate, documented addition rather than a literal
/// port.
///
/// **Durations on the wire.** Go's `time.Duration` is an `int64` nanosecond count and marshals to JSON as a
/// bare integer. To round-trip byte-for-byte with a Go peer (or simply to keep the wire shape consistent
/// with every other duration in this port), ``checkTimeout`` encodes as an integer nanosecond count too,
/// the same convention ``Retry``'s `RetryConfig` and ``FeatureFlags``'s `LaunchDarklyConfig` use.
public struct HealthCheckConfig: Codable, Sendable, Equatable {
  public var checkTimeout: Duration
  public var diskSpace: DiskSpaceCheckerConfig

  public init(
    checkTimeout: Duration = HealthCheckRegistry.defaultCheckTimeout,
    diskSpace: DiskSpaceCheckerConfig = DiskSpaceCheckerConfig()
  ) {
    self.checkTimeout = checkTimeout
    self.diskSpace = diskSpace
  }

  private enum CodingKeys: String, CodingKey {
    case checkTimeout
    case diskSpace
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    checkTimeout = .nanoseconds(
      try c.decodeIfPresent(Int64.self, forKey: .checkTimeout)
        ?? HealthCheckRegistry.defaultCheckTimeout.wholeNanoseconds)
    diskSpace =
      try c.decodeIfPresent(DiskSpaceCheckerConfig.self, forKey: .diskSpace)
      ?? DiskSpaceCheckerConfig()
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(checkTimeout.wholeNanoseconds, forKey: .checkTimeout)
    try c.encode(diskSpace, forKey: .diskSpace)
  }
}
