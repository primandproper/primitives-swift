import Foundation

/// Parses the `text/event-stream` wire format line-by-line into ``Event`` values.
///
/// This is the client-side inverse of platform-go's `sse.sseStream.Send`, which writes an event as
/// `event: <type>\n` (only when `Type` is non-empty) followed by one `data: <line>\n` per line of the
/// payload, terminated by a blank line. Per the [SSE spec](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation),
/// multiple `data:` lines within one frame are rejoined with `"\n"` — the exact inverse of the split
/// Go's sender performs — so a multi-line JSON payload round-trips byte for byte. `id:`/`retry:` fields
/// and comment lines (`:` prefix) are recognized per the general SSE grammar (a client may reasonably
/// talk to any standard SSE server, not just this one) but aren't modeled by ``Event``, so they're
/// consumed and dropped.
///
/// Pure and stateful (accumulates a frame's fields across ``consume(_:)`` calls), so it's testable in
/// isolation from any network transport — see the design note in `PORTING.md` about testing the parser
/// directly rather than driving a live connection.
public struct SSEFrameParser: Sendable {
  private var eventType: String?
  private var dataLines: [String] = []
  private var sawField = false

  public init() {}

  /// Feeds one line, stripped of its trailing line terminator. Returns the completed ``Event`` when the
  /// line is the blank line that dispatches an accumulated frame; returns `nil` while a frame is still
  /// accumulating (including for comment lines and fields `Event` doesn't model).
  public mutating func consume(_ line: String) -> Event? {
    guard !line.isEmpty else {
      guard sawField else { return nil }
      defer { reset() }
      return Event(
        type: eventType ?? "",
        payload: dataLines.isEmpty ? nil : Data(dataLines.joined(separator: "\n").utf8))
    }

    // A line starting with ":" is a comment, ignored per the SSE grammar.
    guard !line.hasPrefix(":") else { return nil }

    let (field, value) = Self.splitField(line)
    switch field {
    case "event":
      eventType = value
    case "data":
      dataLines.append(value)
    default:
      // id/retry/anything else: accepted syntax, but Event has no field for it.
      break
    }
    sawField = true

    return nil
  }

  private mutating func reset() {
    eventType = nil
    dataLines = []
    sawField = false
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
