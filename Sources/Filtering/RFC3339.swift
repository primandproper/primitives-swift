import Foundation

/// RFC3339 date conversion matching platform-go's `time.RFC3339Nano` wire format, used by
/// ``QueryFilter`` for both its URL-param and JSON representations.
///
/// Go emits fractional seconds (trailing zeros trimmed) and parses with `time.RFC3339Nano`. We parse
/// with-or-without fractional seconds and always emit with them. Foundation's `ISO8601DateFormatter`
/// resolves fractional seconds only to millisecond precision, so timestamps carrying sub-millisecond
/// digits round-trip lossily — acceptable here, where these values are client-authored filter bounds,
/// not precise server clocks.
enum RFC3339 {
  static func string(from date: Date) -> String {
    formatter(fractional: true).string(from: date)
  }

  static func date(from string: String) -> Date? {
    formatter(fractional: true).date(from: string)
      ?? formatter(fractional: false).date(from: string)
  }

  // Built per call rather than cached: `ISO8601DateFormatter` isn't `Sendable`, and the call volume
  // here (a handful of filter bounds per request) makes caching pointless. Pike's rule 3 — n is small.
  private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.formatOptions =
      fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    return f
  }
}
