import Foundation

/// Splits a raw byte stream into lines on `\n`, `\r`, or `\r\n`, one byte at a time.
///
/// `SSEEventStream` feeds ``SSEFrameParser`` from this rather than from Foundation's
/// `AsyncSequence.lines` (`AsyncLineSequence`): that type silently **drops empty lines** (verified
/// empirically — `"a\n\nb\n"` yields only `["a", "b"]`, never `""`). SSE's blank line is exactly what
/// dispatches a frame (see ``SSEFrameParser``), so losing it means every event silently fails to
/// dispatch. This hand-rolled splitter preserves blank lines, which is the one property that matters
/// here.
///
/// **Leading BOM.** Per the [SSE spec](https://html.spec.whatwg.org/multipage/server-sent-events.html#stream-bom),
/// a single leading UTF-8 byte order mark (`0xEF 0xBB 0xBF`) is stripped once at the very start of the
/// stream so it doesn't corrupt the first field name. Only that exact three-byte prefix is dropped; a
/// partial or non-BOM opening is replayed unchanged.
struct SSELineSplitter {
  /// Hard cap on the bytes buffered for one line before it is discarded. Without it, a line that never
  /// terminates (a stalled or hostile server that streams forever with no newline) grows ``buffer``
  /// without limit — the line-level analogue of the stream-level unbounded-buffer hazard
  /// ``BoundedEventStream`` guards. platform-go's `sse` package is the *server* write side and never
  /// parses inbound lines, so this bound has no Go analogue; 64 KiB matches Go's `bufio.Scanner` default
  /// `MaxScanTokenSize`, the standard-library "sane maximum token" for line-oriented scanning.
  static let defaultMaxLineLength = 64 * 1024

  private let maxLineLength: Int
  private var buffer: [UInt8] = []
  private var sawCR = false
  /// Set once the current line exceeds ``maxLineLength``: further bytes are dropped and the whole line is
  /// discarded (not truncated-and-emitted) when its terminator arrives, so a broken over-long line can't
  /// masquerade as a valid frame field.
  private var overflowed = false

  init(maxLineLength: Int = SSELineSplitter.defaultMaxLineLength) {
    self.maxLineLength = maxLineLength
  }

  /// Bytes buffered while still deciding whether the stream opens with a UTF-8 BOM. Kept only until the
  /// prefix either matches the full BOM (dropped) or diverges (replayed through the normal path).
  private var bomPending: [UInt8] = []
  private var bomChecked = false
  private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

  /// Feeds one byte. Returns a completed line when a terminator completes it; `nil` while a line is
  /// still accumulating (or when a completed line was dropped for exceeding ``maxLineLength``).
  mutating func consume(_ byte: UInt8) -> String? {
    guard !bomChecked else { return consumeCore(byte) }

    bomPending.append(byte)
    if Self.bom.starts(with: bomPending) {
      if bomPending.count == Self.bom.count {
        // Full BOM matched: drop it and process everything after normally.
        bomChecked = true
        bomPending.removeAll()
      }
      // Still a viable (possibly partial) BOM prefix — keep buffering, emit nothing.
      return nil
    }

    // Not a BOM after all. Replay the buffered bytes through the normal path. Only the last replayed
    // byte can be a line terminator (a real BOM prefix is `0xEF`/`0xBB`, neither of which terminates a
    // line), so at most one completed line can result.
    bomChecked = true
    let pending = bomPending
    bomPending.removeAll(keepingCapacity: true)
    var emitted: String?
    for pendingByte in pending {
      if let line = consumeCore(pendingByte) { emitted = line }
    }
    return emitted
  }

  /// Flushes any buffered, unterminated trailing bytes as a final line — the stream ended without a
  /// closing newline.
  mutating func flush() -> String? {
    if !bomChecked, !bomPending.isEmpty {
      // The stream ended mid-way through what looked like a BOM prefix; those bytes were real content.
      bomChecked = true
      let pending = bomPending
      bomPending.removeAll(keepingCapacity: true)
      for pendingByte in pending { _ = consumeCore(pendingByte) }
    }
    // A trailing line that overflowed ``maxLineLength`` is dropped by ``emitLine()``, same as a
    // terminated one — but it still counts as pending output to flush, hence the `|| overflowed`.
    guard !buffer.isEmpty || overflowed else { return nil }
    return emitLine()
  }

  /// The line-splitting core, unaware of the leading-BOM concern.
  private mutating func consumeCore(_ byte: UInt8) -> String? {
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
      if buffer.count >= maxLineLength {
        // At the cap: stop growing and mark the line for discard rather than buffering unbounded bytes.
        overflowed = true
      } else {
        buffer.append(byte)
      }
      return nil
    }
  }

  private mutating func emitLine() -> String? {
    defer {
      buffer.removeAll(keepingCapacity: true)
      overflowed = false
    }
    return overflowed ? nil : String(decoding: buffer, as: UTF8.self)
  }
}
