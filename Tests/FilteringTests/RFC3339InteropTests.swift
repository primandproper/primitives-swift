import Foundation
import Testing

@testable import Filtering

/// Cross-language interop (REPO-07): variable-precision RFC3339 timestamps emitted by Go's
/// `time.RFC3339Nano`, pinned as literals, that Swift's ``RFC3339`` parsing must accept.
///
/// `time.RFC3339Nano` trims trailing zeros from the fractional part, so the number of fractional
/// digits varies with the instant (`.5`, `.12`, `.123`, `.123456789`, or none at all). These are the
/// shapes a Go peer actually puts on the wire for ``QueryFilter`` bounds, and Swift must parse every
/// one.
///
/// ### Documented precision limit (not a mismatch)
///
/// ``RFC3339`` parses via Foundation's `ISO8601DateFormatter`, which resolves fractional seconds only
/// to **millisecond** precision. Every fixture parses successfully; those carrying sub-millisecond
/// digits (µs/ns) round-trip lossily, truncated to the millisecond — exactly as the ``RFC3339`` doc
/// warns. These are client-authored filter bounds, not precise server clocks, so the loss is
/// acceptable and is asserted here so the behavior is pinned rather than silent.
///
/// ## How the fixtures were produced (reproducible)
///
/// Toolchain `go1.26.4 darwin/arm64`, standard library `time`:
///
/// ```go
/// t := time.Date(2023, 11, 14, 22, 13, 20, 123456789, time.UTC)
/// fmt.Println(t.Format(time.RFC3339Nano)) // "2023-11-14T22:13:20.123456789Z"
/// ```
private struct NanoVector {
  let rfc3339nano: String
  /// The instant's true value in whole nanoseconds since the Unix epoch (`t.UnixNano()`).
  let unixNanos: Int64
  /// Whether Foundation can represent this instant exactly (≤ millisecond fractional precision).
  let exactInSwift: Bool
}

@Suite("RFC3339Nano Go→Swift interop (REPO-07)")
struct RFC3339InteropTests {
  private let vectors: [NanoVector] = [
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20Z", unixNanos: 1_700_000_000_000_000_000, exactInSwift: true),
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20.5Z", unixNanos: 1_700_000_000_500_000_000,
      exactInSwift: true),
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20.12Z", unixNanos: 1_700_000_000_120_000_000,
      exactInSwift: true),
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20.123Z", unixNanos: 1_700_000_000_123_000_000,
      exactInSwift: true),
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20.123456Z", unixNanos: 1_700_000_000_123_456_000,
      exactInSwift: false),
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20.123456789Z", unixNanos: 1_700_000_000_123_456_789,
      exactInSwift: false),
    NanoVector(
      rfc3339nano: "2023-11-14T22:13:20.9Z", unixNanos: 1_700_000_000_900_000_000,
      exactInSwift: true),
    // A non-UTC offset — same instant as the ".123" UTC value, written as -05:00.
    NanoVector(
      rfc3339nano: "2023-11-14T17:13:20.123-05:00", unixNanos: 1_700_000_000_123_000_000,
      exactInSwift: true),
  ]

  @Test("parses every variable-precision RFC3339Nano string Go emits")
  func parsesAll() {
    for v in vectors {
      #expect(RFC3339.date(from: v.rfc3339nano) != nil, "failed to parse \(v.rfc3339nano)")
    }
  }

  @Test("parsed instants match Go to within Foundation's millisecond resolution")
  func matchesToMillisecond() throws {
    for v in vectors {
      let date = try #require(RFC3339.date(from: v.rfc3339nano))
      let gotNanos = Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
      // Difference from Go's true value must be under one millisecond (the sub-ms digits Foundation
      // drops), which also means any offset was resolved to the same absolute instant.
      let deltaNanos = abs(gotNanos - v.unixNanos)
      #expect(deltaNanos < 1_000_000, "\(v.rfc3339nano): off by \(deltaNanos)ns")
    }
  }

  @Test("millisecond-or-coarser fixtures round-trip essentially exactly")
  func exactCasesRoundTrip() throws {
    for v in vectors where v.exactInSwift {
      let date = try #require(RFC3339.date(from: v.rfc3339nano))
      let gotNanos = Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
      // Within a microsecond absorbs only Double(seconds) representation noise, not fractional loss.
      #expect(abs(gotNanos - v.unixNanos) < 1_000, "\(v.rfc3339nano) should be exact")
    }
  }

  @Test("sub-millisecond fixtures truncate to the millisecond (documented ISO8601 limit)")
  func subMillisecondTruncates() throws {
    for v in vectors where !v.exactInSwift {
      let date = try #require(RFC3339.date(from: v.rfc3339nano))
      let gotNanos = Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
      // The µs/ns digits are dropped: the parsed value equals the millisecond-truncated instant.
      let msTruncated = (v.unixNanos / 1_000_000) * 1_000_000
      #expect(
        abs(gotNanos - msTruncated) < 1_000, "\(v.rfc3339nano) should truncate to \(msTruncated)")
      // And it is genuinely lossy versus Go's full-precision value.
      #expect(gotNanos != v.unixNanos)
    }
  }
}
