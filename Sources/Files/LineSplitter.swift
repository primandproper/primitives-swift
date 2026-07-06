/// Splits a raw byte stream into lines on `\n`, `\r\n`, or a bare `\r`, one byte at a time. Ported from
/// platform-go's `Lines` (`bufio.Reader.ReadString('\n')` plus its `trimLineEnding` helper).
///
/// Unlike Foundation's `AsyncSequence.lines` (`AsyncLineSequence`) — which silently **drops empty
/// lines** (`"a\n\nb\n"` yields only `["a", "b"]`, never `""`; the same finding ``EventStream``'s
/// `SSELineSplitter` documents) — this preserves blank lines, matching Go's `bufio`-based reader
/// exactly. It also never caps line length, matching Go's "no 64KB line-length cap" guarantee (unlike
/// `SSELineSplitter`, which imposes one for its own, SSE-specific reason).
struct LineSplitter: Sendable {
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
      return emit()
    case 0x0A:  // \n
      return emit()
    default:
      buffer.append(byte)
      return nil
    }
  }

  /// Flushes any buffered, unterminated trailing bytes as a final line — the source ended without a
  /// closing newline. Returns `nil` if nothing is buffered (a fully-terminated source, or one that ended
  /// exactly on a bare trailing `\r`, which ``consume(_:)`` already emitted).
  mutating func flush() -> String? {
    guard !buffer.isEmpty else { return nil }
    return emit()
  }

  private mutating func emit() -> String {
    defer { buffer.removeAll(keepingCapacity: true) }
    return String(decoding: buffer, as: UTF8.self)
  }
}
