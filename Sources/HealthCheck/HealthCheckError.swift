import Foundation

/// Errors this module throws or classifies. Go's `healthcheck` package carries no error type of its own
/// (checkers return plain `errors.New(...)`/sentinel errors from other packages); this enum covers the
/// cases this port's own registry and concrete checkers introduce.
public enum HealthCheckError: Error, Equatable, Sendable {
  /// A checker did not complete within ``HealthCheckRegistry``'s configured per-check timeout. The Swift
  /// analogue of a Go checker that never returns before its `context.WithTimeout` deadline — except here
  /// the registry itself races the check against the deadline (see ``HealthCheckRegistry/checkAll()``)
  /// rather than relying solely on the checker to notice `ctx.Done()`.
  case timedOut(check: String)

  /// ``ReachabilityChecker`` observed a network path that is not `.satisfied`.
  case unreachable(String)

  /// ``DiskSpaceChecker`` could not read the volume's available capacity for the configured path.
  case diskSpaceUnavailable

  /// ``DiskSpaceChecker`` read the volume's available capacity, but it is below the configured threshold.
  case diskSpaceBelowThreshold(availableBytes: Int64, thresholdBytes: Int64)
}

extension HealthCheckError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .timedOut(let check):
      return "health check \"\(check)\" timed out"
    case .unreachable(let status):
      return "network unreachable (path status: \(status))"
    case .diskSpaceUnavailable:
      return "could not determine available disk space"
    case .diskSpaceBelowThreshold(let available, let threshold):
      return "available disk space (\(available) bytes) is below threshold (\(threshold) bytes)"
    }
  }
}
