import Foundation
import Testing

@testable import EventStream

/// Feeds raw bytes through a fresh splitter (optionally with a custom line cap), returning every
/// completed line (including blank ones, but not lines dropped for exceeding the cap).
private func splitLines(_ bytes: [UInt8], maxLineLength: Int? = nil) -> [String] {
  var splitter =
    maxLineLength.map { SSELineSplitter(maxLineLength: $0) } ?? SSELineSplitter()
  var lines: [String] = []
  for byte in bytes {
    if let line = splitter.consume(byte) {
      lines.append(line)
    }
  }
  if let line = splitter.flush() {
    lines.append(line)
  }
  return lines
}

@Suite("SSELineSplitter")
struct SSELineSplitterTests {
  @Test("splits on \\n and preserves a blank line between two newlines")
  func splitsOnLFPreservingBlankLines() {
    let lines = splitLines(Array("event: only\ndata: {}\n\n".utf8))
    #expect(lines == ["event: only", "data: {}", ""])
  }

  @Test("Foundation's AsyncSequence.lines drops this exact blank line; this splitter must not")
  func regressionAgainstFoundationsLinesBehavior() {
    // Empirically, `AsyncLineSequence` yields only ["a", "b"] for "a\n\nb\n" — it silently drops the
    // blank line, which is exactly the SSE frame boundary. This is why SSEEventStream doesn't use it.
    let lines = splitLines(Array("a\n\nb\n".utf8))
    #expect(lines == ["a", "", "b"])
  }

  @Test("splits on \\r\\n")
  func splitsOnCRLF() {
    let lines = splitLines(Array("event: x\r\ndata: {}\r\n\r\n".utf8))
    #expect(lines == ["event: x", "data: {}", ""])
  }

  @Test("splits on a lone \\r")
  func splitsOnLoneCR() {
    let lines = splitLines(Array("event: x\rdata: {}\r\r".utf8))
    #expect(lines == ["event: x", "data: {}", ""])
  }

  @Test("a trailing unterminated line is flushed")
  func flushesTrailingUnterminatedLine() {
    let lines = splitLines(Array("event: x\ndata: {}".utf8))
    #expect(lines == ["event: x", "data: {}"])
  }

  @Test("flush is a no-op when the buffer is empty")
  func flushOnEmptyBufferIsNil() {
    var splitter = SSELineSplitter()
    #expect(splitter.flush() == nil)
    _ = splitter.consume(0x0A)  // "\n" with nothing buffered: emits an empty line
    #expect(splitter.flush() == nil)
  }

  @Test("consecutive blank lines are all preserved")
  func consecutiveBlankLinesPreserved() {
    let lines = splitLines(Array("a\n\n\nb\n".utf8))
    #expect(lines == ["a", "", "", "b"])
  }

  @Test("feeding a byte at a time yields identical results to a full buffer")
  func byteAtATimeMatchesWholeBuffer() {
    let input = Array("event: chunked\ndata: {\"a\":1}\ndata: {\"b\":2}\n\n".utf8)
    #expect(splitLines(input) == ["event: chunked", "data: {\"a\":1}", "data: {\"b\":2}", ""])
  }

  @Test("a line over the cap is dropped whole; a following line still parses")
  func overLongLineIsDroppedWhole() {
    // The 14-byte first line exceeds an 8-byte cap and is discarded entirely (not truncated-and-emitted);
    // the healthy line after it is unaffected.
    let lines = splitLines(Array("waytoolongvalue\nok\n".utf8), maxLineLength: 8)
    #expect(lines == ["ok"])
  }

  @Test("a line exactly at the cap is still emitted")
  func lineAtCapIsEmitted() {
    let lines = splitLines(Array("data\n".utf8), maxLineLength: 4)
    #expect(lines == ["data"])
  }

  @Test("a trailing unterminated over-long line is dropped by flush, not grown without limit")
  func trailingOverLongLineDroppedByFlush() {
    // No closing newline: flush() must still discard the over-cap line rather than emit a giant string.
    let lines = splitLines(Array("thisisfartoolongtokeep".utf8), maxLineLength: 8)
    #expect(lines == [])
  }

  @Test("the buffer never exceeds the cap even for a pathological unterminated line")
  func bufferBoundedForUnterminatedLine() {
    var splitter = SSELineSplitter(maxLineLength: 16)
    for byte in Array(String(repeating: "x", count: 10_000).utf8) {
      _ = splitter.consume(byte)
    }
    // The over-long line is dropped, proving nothing accumulated past the cap.
    #expect(splitter.flush() == nil)
  }

  @Test("the default cap is 64 KiB, matching Go's bufio.Scanner MaxScanTokenSize")
  func defaultCapMatchesBufioScanner() {
    #expect(SSELineSplitter.defaultMaxLineLength == 64 * 1024)
  }

  @Test("a leading UTF-8 BOM is stripped so the first field name isn't corrupted")
  func stripsLeadingBOM() {
    // "\u{FEFF}" encodes to the 3-byte UTF-8 BOM 0xEF 0xBB 0xBF. Without stripping, the first line would
    // read "\u{FEFF}event: x" and its field name would no longer be "event".
    let lines = splitLines(Array("\u{FEFF}event: x\ndata: {}\n\n".utf8))
    #expect(lines == ["event: x", "data: {}", ""])
  }

  @Test("only a leading BOM is stripped; a mid-stream BOM is preserved")
  func onlyLeadingBOMStripped() {
    // A BOM that isn't at byte zero is ordinary content and must survive.
    let lines = splitLines(Array("data: a\ndata: \u{FEFF}b\n\n".utf8))
    #expect(lines == ["data: a", "data: \u{FEFF}b", ""])
  }

  @Test("a lone 0xEF that isn't a BOM is replayed, not swallowed")
  func nonBOMLeadingByteReplayed() {
    // 0xEF followed by a newline is not a BOM prefix; the byte is real (if invalid-UTF-8) content and
    // must still produce a line rather than being dropped as a partial BOM.
    let lines = splitLines([0xEF, 0x0A, 0x61, 0x0A])  // <0xEF>\n a \n
    #expect(lines.count == 2)
    #expect(lines[1] == "a")
  }
}
