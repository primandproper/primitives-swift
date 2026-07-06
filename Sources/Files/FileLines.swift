import Foundation

/// An `AsyncSequence` of a file's lines, opened via `FileHandle` and closed automatically — the
/// file-backed counterpart to ``LineSequence``. Ported from platform-go's `files.LinesFile`
/// (`lines_file.go`), including that the open error is thrown synchronously (mirrors
/// `errors.Wrap(err, "opening file")`) while a read error surfaces later, from iteration.
///
/// The file handle closes when iteration completes normally, when a read fails, and — unlike a plain
/// `struct`-based `AsyncSequence` — even if the caller abandons iteration early (breaks out of a
/// `for await` loop, or simply drops the sequence without finishing it): closing is driven by
/// ``AsyncIterator``'s `deinit`, not by a completion callback the consumer must remember to trigger.
/// This is actually a stronger guarantee than Go's `LinesFile`, whose `defer r.closeQuietly(f)` only
/// runs once the generator function itself returns (i.e., once `range` completes or `break`s) — and a
/// direct improvement on Go's `StreamChunksFile`, which documents a real leak hazard for a consumer that
/// neither drains the channel nor cancels its `context.Context`.
public final class FileLines: AsyncSequence, Sendable {
  public typealias Element = String

  private let handle: FileHandle

  /// Opens `path` for reading.
  /// - Throws: the underlying `FileHandle` open error if `path` does not exist or isn't readable.
  public init(path: String) throws {
    handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(handle: handle)
  }

  public final class AsyncIterator: AsyncIteratorProtocol {
    private let handle: FileHandle
    private var bytesIterator: FileHandle.AsyncBytes.AsyncIterator
    private var splitter = LineSplitter()
    private var closed = false

    fileprivate init(handle: FileHandle) {
      self.handle = handle
      self.bytesIterator = handle.bytes.makeAsyncIterator()
    }

    public func next() async throws -> String? {
      while true {
        do {
          guard let byte = try await bytesIterator.next() else {
            closeQuietly()
            return splitter.flush()
          }

          if let line = splitter.consume(byte) {
            return line
          }
        } catch {
          closeQuietly()
          throw error
        }
      }
    }

    private func closeQuietly() {
      guard !closed else { return }
      closed = true
      try? handle.close()
    }

    deinit {
      guard !closed else { return }
      try? handle.close()
    }
  }
}
