import Foundation

/// `Duration` ↔ Go-wire conversions, this module's copy of the `wholeNanoseconds`/`timeInterval` shim
/// `HTTPClientConfig`, `LaunchDarklyConfig`, and `Sources/LLM`'s `DurationWire` each carry (folding these
/// onto one shared definition needs a low-level target every module can depend on, tracked as a
/// cross-module follow-up rather than done here).
///
/// Go's `time.Duration` is a nanosecond count that marshals to JSON as a bare integer: ``wholeNanoseconds``
/// produces that integer on the way out (truncating any sub-nanosecond resolution) and `.nanoseconds(_:)`
/// rebuilds a `Duration` on the way in. ``timeInterval`` bridges to the seconds `URLSessionConfiguration`
/// timeouts expect.
extension Duration {
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }

  var timeInterval: TimeInterval {
    let (seconds, attoseconds) = components
    return Double(seconds) + Double(attoseconds) / 1e18
  }
}
