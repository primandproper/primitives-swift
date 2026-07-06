import Foundation

/// `Duration` ↔ Go-wire conversions — the canonical `DurationWire` helper (REPO-12), collecting the
/// `time.Duration` marshalling shims this port would otherwise repeat inline.
///
/// Go's `time.Duration` is a nanosecond count that marshals to JSON as a bare integer: ``wholeNanoseconds``
/// produces that integer on the way out (truncating any sub-nanosecond resolution) and `.nanoseconds(_:)`
/// rebuilds a `Duration` on the way in. ``timeInterval`` bridges to the seconds `URLSessionConfiguration`
/// timeouts expect.
///
/// Scope note: this collapses the LLM module's copies onto one definition. Five sibling targets still
/// carry their own identical `internal` copy — `HTTPClient` (`HTTPClientConfig`), `Retry` (`RetryConfig`,
/// `ExponentialBackoffPolicy`), `EventStream` (`WebSocketEventStreamConfig`), `FeatureFlags`
/// (`LaunchDarklyConfig`), and `Cookies` (`CookieConfig`). Folding those in needs a shared low-level
/// target they can all depend on (and a `Package.swift` edit), so it's left as a cross-module follow-up
/// rather than reaching across target boundaries here.
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
