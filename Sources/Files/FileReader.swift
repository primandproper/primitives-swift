/// Reads files by name, ported from platform-go's `files.Reader` (`files.go`).
///
/// Go's `LinesFile`/`ChunksFile` return a pull-driven `iter.Seq2`, so cancellation is owned entirely by
/// the caller's `range`/`break`; `StreamChunksFile` instead streams off a background goroutine over a
/// channel, requiring the caller to either drain it or cancel a `context.Context` to avoid leaking the
/// goroutine. Swift's `AsyncSequence` already unifies both shapes — iteration is cooperatively
/// pull-driven no matter how the producer is implemented — so this port collapses `ChunksFile` and
/// `StreamChunksFile` into the single ``chunks(atPath:size:)``.
///
/// The return type is the concrete `AsyncThrowingStream` rather than `any AsyncSequence<Element, Error>`
/// (which existentializes fine at the call site but requires the primary-associated-type `Failure`
/// existential, only available starting macOS 15/iOS 18 — newer than this port's macOS 13/iOS 16 floor).
/// ``LiveFileReader`` bridges its pull-based ``FileLines``/``ChunkSequence`` into a stream internally;
/// see `FileReaderStreamBridge.swift`.
///
/// Dropped entirely: the `Observer`/logger/tracer-provider threading Go's `standardReader` carries
/// (`NewReader(logger, tracerProvider)`). This module has no dependency on `Observability` (per the port
/// task), and ``Encoding``'s own `ClientEncoder` already made the same call for the identical reason — a
/// caller that wants a span around a read wraps the call at its own layer.
public protocol FileReader: Sendable {
  /// Opens `path` and yields each of its lines. The open error throws synchronously; a read error
  /// surfaces later, by throwing from the returned stream's iteration. Mirrors Go's `LinesFile`.
  func lines(atPath path: String) throws -> AsyncThrowingStream<String, Error>

  /// Opens `path` and yields successive chunks of up to `size` lines; the final chunk may be shorter.
  /// Mirrors Go's `ChunksFile`/`StreamChunksFile` (collapsed into one — see the protocol documentation
  /// above).
  /// - Throws: ``FilesError/nonPositiveChunkSize`` synchronously if `size` is not greater than zero, or
  ///   the underlying file-open error.
  func chunks(atPath path: String, size: Int) throws -> AsyncThrowingStream<[String], Error>

  /// Opens `path` and returns up to `count` lines after skipping `offset` lines. Mirrors Go's
  /// `SliceLinesFile`.
  func sliceLines(atPath path: String, offset: Int, count: Int) async throws -> [String]
}
