import Foundation

extension Duration {
  /// This duration as a whole count of nanoseconds — the unit Go's `time.Duration` uses natively and
  /// marshals to JSON as a bare integer. Truncates any sub-nanosecond resolution.
  ///
  /// `HTTPClient` and `Retry` each carry an identical `internal` copy of this helper; per the port's
  /// convention of not reaching across target boundaries for a two-line conversion, this module carries
  /// its own.
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
