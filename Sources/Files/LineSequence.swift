/// An `AsyncSequence` that splits a raw byte source into lines, ported from platform-go's
/// `files.Lines(io.Reader)`. Wraps any byte-producing `AsyncSequence` — most usefully
/// `FileHandle.bytes` (see ``FileLines``, the file-backed, self-closing counterpart) — the same way
/// Go's version wraps any `io.Reader`.
///
/// An unterminated final line is still yielded (mirrors Go). A read error surfaces by throwing from
/// ``AsyncIterator/next()``; any bytes buffered for an in-progress, not-yet-terminated line at that
/// point are discarded rather than surfaced as a truncated "good" line, matching Go's `Lines`, which
/// "does not yield a truncated fragment as a good line on a read error."
public struct LineSequence<Bytes: AsyncSequence & Sendable>: AsyncSequence, Sendable
where Bytes.Element == UInt8 {
  public typealias Element = String

  private let bytes: Bytes

  public init(bytes: Bytes) {
    self.bytes = bytes
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(bytesIterator: bytes.makeAsyncIterator())
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var bytesIterator: Bytes.AsyncIterator
    private var splitter = LineSplitter()
    private var finished = false

    init(bytesIterator: Bytes.AsyncIterator) {
      self.bytesIterator = bytesIterator
    }

    public mutating func next() async throws -> String? {
      guard !finished else { return nil }

      while true {
        guard let byte = try await bytesIterator.next() else {
          finished = true
          return splitter.flush()
        }

        if let line = splitter.consume(byte) {
          return line
        }
      }
    }
  }
}
