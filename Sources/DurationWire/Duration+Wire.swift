import Foundation

/// `Duration` ↔ Go-wire conversions — the canonical, shared Go-wire duration helper (REPO-12).
///
/// This is the single low-level home for the `time.Duration` marshalling shims the port would otherwise
/// repeat inline in every module that speaks the Go JSON contract. It carries no dependencies so any
/// target can depend on it without pulling in a transitive graph.
///
/// Go's `time.Duration` is a nanosecond count that marshals to JSON as a bare integer: ``wholeNanoseconds``
/// produces that integer on the way out (truncating any sub-nanosecond resolution) and `.nanoseconds(_:)`
/// rebuilds a `Duration` on the way in. ``timeInterval`` bridges to the seconds `URLSessionConfiguration`
/// timeouts expect.
extension Duration {
  /// Builds a `Duration` from a whole count of nanoseconds — the unit Go's `time.Duration` uses
  /// natively and marshals to JSON as a bare integer, so a config timeout arriving over the wire is a
  /// plain nanosecond count.
  public init(wireNanoseconds nanoseconds: Int64) {
    self = .nanoseconds(nanoseconds)
  }

  /// This duration as a whole count of nanoseconds — the unit Go's `time.Duration` uses natively and
  /// marshals to JSON as a bare integer. Truncates any sub-nanosecond resolution.
  public var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }

  /// This duration as a whole count of milliseconds — e.g. the unit SQLite's `busy_timeout` PRAGMA
  /// expects. Truncates any sub-millisecond resolution.
  public var wholeMilliseconds: Int64 {
    wholeNanoseconds / 1_000_000
  }

  /// This duration as `TimeInterval` (seconds), the unit `URLSessionConfiguration` timeouts expect.
  public var timeInterval: TimeInterval {
    let (seconds, attoseconds) = components
    return Double(seconds) + Double(attoseconds) / 1e18
  }
}
