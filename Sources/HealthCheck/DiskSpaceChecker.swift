import Foundation

/// A ``Checker`` reporting whether a volume has at least a configured amount of free space, backed by
/// `URL`'s `.volumeAvailableCapacityForImportantUsageKey` resource value. Go's `healthcheck` package has no
/// disk-space checker (a server process typically monitors host disk pressure out-of-band, e.g. via its
/// orchestrator); this is new surface for the iOS port, filling the "disk-space" item called out in
/// `PORTING.md`'s Wave 5 plan — an on-device app is the one process actually positioned to notice it's
/// about to fail a local write.
public struct DiskSpaceChecker: Checker {
  /// Default free-space floor: 50 MB, a conservative "enough room for a database checkpoint or a cache
  /// write" threshold. Callers with a more specific requirement should pass their own.
  public static let defaultMinimumFreeBytes: Int64 = 50 * 1024 * 1024

  public let name: String
  /// The volume to inspect. Defaults to the app's home directory, whose volume is always present on iOS.
  public let path: URL
  public let minimumFreeBytes: Int64

  public init(
    name: String = "disk-space",
    path: URL = URL(fileURLWithPath: NSHomeDirectory()),
    minimumFreeBytes: Int64 = DiskSpaceChecker.defaultMinimumFreeBytes
  ) {
    self.name = name
    self.path = path
    self.minimumFreeBytes = minimumFreeBytes
  }

  public func check() async throws {
    let values: URLResourceValues
    do {
      values = try path.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    } catch {
      throw HealthCheckError.diskSpaceUnavailable
    }
    guard let available = values.volumeAvailableCapacityForImportantUsage else {
      throw HealthCheckError.diskSpaceUnavailable
    }
    guard available >= minimumFreeBytes else {
      throw HealthCheckError.diskSpaceBelowThreshold(
        availableBytes: available, thresholdBytes: minimumFreeBytes)
    }
  }
}
