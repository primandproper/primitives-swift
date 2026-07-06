import Testing

@testable import Files

@Suite("FileReaderMock")
struct FileReaderMockTests {
  @Test("default handlers return empty results and never throw")
  func defaults() async throws {
    let mock = FileReaderMock()

    var lines: [String] = []
    for try await line in try mock.lines(atPath: "a.txt") { lines.append(line) }
    #expect(lines.isEmpty)

    var chunks: [[String]] = []
    for try await chunk in try mock.chunks(atPath: "a.txt", size: 2) { chunks.append(chunk) }
    #expect(chunks.isEmpty)

    #expect(try await mock.sliceLines(atPath: "a.txt", offset: 0, count: 1).isEmpty)
  }

  @Test("records call arguments")
  func recordsCalls() async throws {
    let mock = FileReaderMock()

    _ = try mock.lines(atPath: "a.txt")
    _ = try mock.chunks(atPath: "b.txt", size: 5)
    _ = try await mock.sliceLines(atPath: "c.txt", offset: 2, count: 3)

    #expect(mock.linesCalls == ["a.txt"])
    #expect(mock.chunksCalls == [FileReaderMock.ChunksCall(path: "b.txt", size: 5)])
    #expect(
      mock.sliceLinesCalls == [FileReaderMock.SliceLinesCall(path: "c.txt", offset: 2, count: 3)])
  }

  @Test("handlers can inject custom behavior, including throwing")
  func customHandlers() async throws {
    let mock = FileReaderMock(
      linesHandler: { _ in
        AsyncThrowingStream<String, Error> { continuation in
          continuation.yield("stubbed")
          continuation.finish()
        }
      },
      chunksHandler: { _, _ in throw FilesError.nonPositiveChunkSize },
      sliceLinesHandler: { _, _, _ in ["stubbed-line"] }
    )

    var lines: [String] = []
    for try await line in try mock.lines(atPath: "a.txt") { lines.append(line) }
    #expect(lines == ["stubbed"])

    #expect(throws: FilesError.nonPositiveChunkSize) {
      _ = try mock.chunks(atPath: "a.txt", size: 1)
    }

    let got = try await mock.sliceLines(atPath: "a.txt", offset: 0, count: 1)
    #expect(got == ["stubbed-line"])
  }
}
