/// An `AsyncSequence` that groups a line source into fixed-size chunks, ported from platform-go's
/// `files.Chunks(io.Reader, n)`. The final chunk may hold fewer than `size` lines. A read error from the
/// underlying line source surfaces the same way ``LineSequence`` surfaces it — by throwing from
/// ``AsyncIterator/next()`` — discarding any in-progress partial chunk, matching Go's `Chunks`.
public struct ChunkSequence<Lines: AsyncSequence & Sendable>: AsyncSequence, Sendable
where Lines.Element == String {
  public typealias Element = [String]

  private let lines: Lines
  private let size: Int

  /// - Precondition: `size > 0`. Callers should validate up front (see `chunks(from:size:)` and
  ///   ``FileReader/chunks(atPath:size:)``, both of which throw ``FilesError/nonPositiveChunkSize``
  ///   before ever constructing a ``ChunkSequence``) rather than discovering a bad size mid-iteration.
  init(lines: Lines, size: Int) {
    self.lines = lines
    self.size = size
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(linesIterator: lines.makeAsyncIterator(), size: size)
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var linesIterator: Lines.AsyncIterator
    private let size: Int
    private var finished = false

    init(linesIterator: Lines.AsyncIterator, size: Int) {
      self.linesIterator = linesIterator
      self.size = size
    }

    public mutating func next() async throws -> [String]? {
      guard !finished else { return nil }

      var chunk: [String] = []
      chunk.reserveCapacity(size)

      while chunk.count < size {
        guard let line = try await linesIterator.next() else {
          finished = true
          return chunk.isEmpty ? nil : chunk
        }
        chunk.append(line)
      }

      return chunk
    }
  }
}
