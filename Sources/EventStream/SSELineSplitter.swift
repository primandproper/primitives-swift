import Foundation

/// Splits a raw byte stream into lines on `\n`, `\r`, or `\r\n`, one byte at a time.
///
/// `SSEEventStream` feeds ``SSEFrameParser`` from this rather than from Foundation's
/// `AsyncSequence.lines` (`AsyncLineSequence`): that type silently **drops empty lines** (verified
/// empirically — `"a\n\nb\n"` yields only `["a", "b"]`, never `""`). SSE's blank line is exactly what
/// dispatches a frame (see ``SSEFrameParser``), so losing it means every event silently fails to
/// dispatch. This hand-rolled splitter preserves blank lines, which is the one property that matters
/// here.
struct SSELineSplitter {
  private var buffer: [UInt8] = []
  private var sawCR = false

  /// Feeds one byte. Returns a completed line when a terminator completes it; `nil` while a line is
  /// still accumulating.
  mutating func consume(_ byte: UInt8) -> String? {
    if sawCR {
      sawCR = false
      if byte == 0x0A {
        // The second half of a \r\n pair; the line was already emitted on the \r.
        return nil
      }
      // Not a pair: fall through and process `byte` normally below.
    }

    switch byte {
    case 0x0D:  // \r
      sawCR = true
      return emitLine()
    case 0x0A:  // \n
      return emitLine()
    default:
      buffer.append(byte)
      return nil
    }
  }

  /// Flushes any buffered, unterminated trailing bytes as a final line — the stream ended without a
  /// closing newline.
  mutating func flush() -> String? {
    guard !buffer.isEmpty else { return nil }
    return emitLine()
  }

  private mutating func emitLine() -> String {
    defer { buffer.removeAll(keepingCapacity: true) }
    return String(decoding: buffer, as: UTF8.self)
  }
}
