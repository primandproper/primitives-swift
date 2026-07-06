import Foundation

/// Parses the `text/event-stream` wire format line-by-line into ``Event`` values.
///
/// This is the client-side inverse of platform-go's `sse.sseStream.Send`, which writes an event as
/// `event: <type>\n` (only when `Type` is non-empty) followed by one `data: <line>\n` per line of the
/// payload, terminated by a blank line. Per the [SSE spec](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation),
/// multiple `data:` lines within one frame are rejoined with `"\n"` — the exact inverse of the split
/// Go's sender performs — so a multi-line JSON payload round-trips byte for byte.
///
/// **`id:` and `retry:`.** Unlike ``Event`` (which models only `type`/`payload`, mirroring Go's server
/// `Event`), the *reconnection* fields are retained for a reconnecting wrapper to read: ``lastEventID``
/// tracks the server's `id:` (sent back as `Last-Event-ID` on resume) and ``reconnectionTime`` tracks a
/// server-suggested `retry:` value. Per WHATWG, the last-event-ID buffer is **not** reset between events
/// (only overwritten when an `id` field without a U+0000 NUL arrives), and a `retry:` value is honored
/// only when it is an ASCII-digit string (otherwise ignored). Comment lines (`:` prefix) are ignored per
/// the general SSE grammar.
///
/// **Empty-data frames.** Per the spec's dispatch step, a frame whose data buffer is empty dispatches
/// nothing — so a lone `event: heartbeat` with no `data:` line produces no ``Event`` (its `id:`/`retry:`
/// side effects still apply). This diverges from Go's server, which never emits such a frame, so nothing
/// on the write side depends on the old "dispatch a type-only event with a nil payload" behavior.
///
/// Pure and stateful (accumulates a frame's fields across ``consume(_:)`` calls), so it's testable in
/// isolation from any network transport — see the design note in `PORTING.md` about testing the parser
/// directly rather than driving a live connection.
public struct SSEFrameParser: Sendable {
  private var eventType: String?
  private var dataLines: [String] = []

  /// The most recent non-NUL `id:` value seen, persisted across events per WHATWG. A reconnecting wrapper
  /// sends this back as `Last-Event-ID` on resume. `nil` until the server sends an `id:` field.
  public private(set) var lastEventID: String?

  /// The most recent valid `retry:` value, as a reconnection delay. A reconnecting wrapper uses it as the
  /// floor for its re-dial backoff. `nil` until the server sends a well-formed (ASCII-digit) `retry:`.
  public private(set) var reconnectionTime: Duration?

  public init() {}

  /// Feeds one line, stripped of its trailing line terminator. Returns the completed ``Event`` when the
  /// line is the blank line that dispatches an accumulated frame *and* that frame carried at least one
  /// `data:` line; returns `nil` while a frame is still accumulating (including for comment lines, empty
  /// frames, and `id:`/`retry:`-only frames).
  public mutating func consume(_ line: String) -> Event? {
    guard !line.isEmpty else {
      // Per the WHATWG dispatch step, a frame with an empty data buffer dispatches nothing; the event
      // type and data buffers are still reset (the last-event-ID buffer is deliberately not).
      defer { reset() }
      guard !dataLines.isEmpty else { return nil }
      return Event(
        type: eventType ?? "",
        payload: Data(dataLines.joined(separator: "\n").utf8))
    }

    // A line starting with ":" is a comment, ignored per the SSE grammar.
    guard !line.hasPrefix(":") else { return nil }

    let (field, value) = Self.splitField(line)
    switch field {
    case "event":
      eventType = value
    case "data":
      dataLines.append(value)
    case "id":
      // Ignore an id containing a NUL, per WHATWG; otherwise it persists as the last event ID.
      if !value.contains("\u{0000}") {
        lastEventID = value
      }
    case "retry":
      // Only an ASCII-digit string is a valid reconnection time (in milliseconds); anything else is
      // ignored rather than clearing the previous value.
      if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let ms = Int64(value) {
        reconnectionTime = .milliseconds(ms)
      }
    default:
      // Any other field is accepted syntax but unmodeled.
      break
    }

    return nil
  }

  private mutating func reset() {
    eventType = nil
    dataLines = []
  }

  /// Splits a raw field line on its first `:`, stripping a single leading space from the value per the
  /// SSE spec. A line with no colon is the field name with an empty value.
  private static func splitField(_ line: String) -> (field: String, value: String) {
    guard let colonIndex = line.firstIndex(of: ":") else {
      return (line, "")
    }
    let field = String(line[line.startIndex..<colonIndex])
    var value = String(line[line.index(after: colonIndex)...])
    if value.hasPrefix(" ") {
      value.removeFirst()
    }
    return (field, value)
  }
}
