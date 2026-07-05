import Foundation
import Testing

@testable import EventStream

/// Feeds raw bytes through a fresh splitter, returning every completed line (including blank ones).
private func splitLines(_ bytes: [UInt8]) -> [String] {
  var splitter = SSELineSplitter()
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
}
