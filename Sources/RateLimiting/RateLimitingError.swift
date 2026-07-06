import Foundation

/// Errors thrown while validating or building a ``RateLimiter`` from ``RateLimitingConfig``.
///
/// Go spreads the equivalent failures across two independent, uncoupled checks — `ozzo-validation`'s
/// `ValidateWithContext` rejects a negative rate/burst, while `ProvideRateLimiter`'s `switch` on
/// `Provider` separately returns `errors.Newf("unknown rate limiter provider: %q", ...)` for anything
/// unrecognized — and never calls the former from the latter. This port keeps that same decoupling: see
/// ``RateLimitingConfig/validate()`` and ``RateLimitingConfig/provideRateLimiter(pillars:)``.
public enum RateLimitingError: Error, Equatable, Sendable {
  /// ``RateLimitingConfig/requestsPerSecond`` was negative. Thrown by ``RateLimitingConfig/validate()``.
  case invalidRequestsPerSecond(Double)

  /// ``RateLimitingConfig/burstSize`` was negative. Thrown by ``RateLimitingConfig/validate()``.
  case invalidBurstSize(Int)

  /// ``RateLimitingConfig/provider`` was neither empty, `"noop"`, nor `"memory"`. Thrown by
  /// ``RateLimitingConfig/provideRateLimiter(pillars:)``, mirroring Go's `default` switch case.
  case unknownProvider(String)
}

extension RateLimitingError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidRequestsPerSecond(let value):
      return "invalid rate limiting requestsPerSecond: \(value) (must be >= 0)"
    case .invalidBurstSize(let value):
      return "invalid rate limiting burstSize: \(value) (must be >= 0)"
    case .unknownProvider(let provider):
      return "unknown rate limiter provider: \"\(provider)\""
    }
  }
}
