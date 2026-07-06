import Foundation
import Testing

@testable import Files

@Suite("LiveFileReader")
struct LiveFileReaderTests {
  private func makeFile(_ contents: String) throws -> String {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .path
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  @Test("lines(atPath:) iterates a file's lines")
  func linesIteratesFile() async throws {
    let path = try makeFile("a\nb\nc\n")
    let reader: any FileReader = LiveFileReader()

    var out: [String] = []
    for try await line in try reader.lines(atPath: path) {
      out.append(line)
    }
    #expect(out == ["a", "b", "c"])
  }

  @Test("lines(atPath:) yields an unterminated final line (no trailing newline)")
  func linesNoTrailingNewline() async throws {
    let path = try makeFile("a\nb\nc")
    let reader: any FileReader = LiveFileReader()

    var out: [String] = []
    for try await line in try reader.lines(atPath: path) {
      out.append(line)
    }
    #expect(out == ["a", "b", "c"])
  }

  @Test("lines(atPath:) on a missing file throws synchronously")
  func linesMissingFile() throws {
    let reader: any FileReader = LiveFileReader()
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path

    #expect(throws: (any Error).self) {
      _ = try reader.lines(atPath: path)
    }
  }

  @Test("chunks(atPath:size:) groups a file's lines")
  func chunksGroupsFile() async throws {
    let path = try makeFile("a\nb\nc\n")
    let reader: any FileReader = LiveFileReader()

    var out: [[String]] = []
    for try await chunk in try reader.chunks(atPath: path, size: 2) {
      out.append(chunk)
    }
    #expect(out == [["a", "b"], ["c"]])
  }

  @Test("chunks(atPath:size:) rejects a non-positive size synchronously")
  func chunksNonPositiveSize() throws {
    let path = try makeFile("a\n")
    let reader: any FileReader = LiveFileReader()

    #expect(throws: FilesError.nonPositiveChunkSize) {
      _ = try reader.chunks(atPath: path, size: 0)
    }
  }

  @Test("sliceLines(atPath:offset:count:) returns a window of a file")
  func windowedReadOfFile() async throws {
    let path = try makeFile("l0\nl1\nl2\nl3\nl4\n")
    let reader: any FileReader = LiveFileReader()

    let got = try await reader.sliceLines(atPath: path, offset: 1, count: 2)
    #expect(got == ["l1", "l2"])
  }

  @Test("sliceLines(atPath:offset:count:) on a missing file throws")
  func windowedReadMissingFile() async throws {
    let reader: any FileReader = LiveFileReader()
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path

    await #expect(throws: (any Error).self) {
      _ = try await reader.sliceLines(atPath: path, offset: 0, count: 1)
    }
  }
}
