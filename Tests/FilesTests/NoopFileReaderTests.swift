import Testing

@testable import Files

@Suite("NoopFileReader")
struct NoopFileReaderTests {
  private var reader: any FileReader { NoopFileReader() }

  @Test("lines(atPath:) yields nothing")
  func lines() async throws {
    var out: [String] = []
    for try await line in try reader.lines(atPath: "ignored") {
      out.append(line)
    }
    #expect(out.isEmpty)
  }

  @Test("chunks(atPath:size:) yields nothing")
  func chunks() async throws {
    var out: [[String]] = []
    for try await chunk in try reader.chunks(atPath: "ignored", size: 10) {
      out.append(chunk)
    }
    #expect(out.isEmpty)
  }

  @Test("sliceLines(atPath:offset:count:) returns an empty array")
  func sliceLines() async throws {
    let got = try await reader.sliceLines(atPath: "ignored", offset: 0, count: 10)
    #expect(got.isEmpty)
  }
}
