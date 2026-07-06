/// The live ``FileReader``, backed by `FileHandle` via ``FileLines``. Ported from platform-go's
/// `standardReader` (`files.go`, `lines_file.go`), minus the observability threading — see
/// ``FileReader``.
public struct LiveFileReader: FileReader {
  public init() {}

  public func lines(atPath path: String) throws -> AsyncThrowingStream<String, Error> {
    bridgeToThrowingStream(try FileLines(path: path))
  }

  public func chunks(atPath path: String, size: Int) throws -> AsyncThrowingStream<[String], Error>
  {
    guard size > 0 else { throw FilesError.nonPositiveChunkSize }
    return bridgeToThrowingStream(ChunkSequence(lines: try FileLines(path: path), size: size))
  }

  public func sliceLines(atPath path: String, offset: Int, count: Int) async throws -> [String] {
    try await sliceLinesOfLines(from: try FileLines(path: path), offset: offset, count: count)
  }
}
