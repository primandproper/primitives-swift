import Testing

@testable import Files

@Suite("chunks(from:size:)")
struct ChunksTests {
  private func collect(_ string: String, size: Int) async throws -> [[String]] {
    var out: [[String]] = []
    for try await chunk in try chunks(from: ThrowingByteSequence(string), size: size) {
      out.append(chunk)
    }
    return out
  }

  @Test("yields chunks of n lines with a short final chunk")
  func chunksOfN() async throws {
    #expect(try await collect("a\nb\nc\nd\ne\n", size: 2) == [["a", "b"], ["c", "d"], ["e"]])
  }

  @Test("a chunk size evenly dividing the input has no short final chunk")
  func evenDivision() async throws {
    #expect(try await collect("a\nb\nc\nd\n", size: 2) == [["a", "b"], ["c", "d"]])
  }

  @Test("non-positive n throws ErrNonPositiveChunkSize synchronously")
  func nonPositiveChunkSize() throws {
    #expect(throws: FilesError.nonPositiveChunkSize) {
      _ = try chunks(from: ThrowingByteSequence("a\n"), size: 0)
    }
    #expect(throws: FilesError.nonPositiveChunkSize) {
      _ = try chunks(from: ThrowingByteSequence("a\n"), size: -1)
    }
  }

  @Test("a read error discards the in-progress partial chunk")
  func readErrorDiscardsPartialChunk() async throws {
    let sentinel = SentinelError(id: "boom")
    var seen: [[String]] = []
    do {
      for try await chunk in try chunks(
        from: ThrowingByteSequence("a\nb\n", thenThrow: sentinel), size: 3)
      {
        seen.append(chunk)
      }
      Issue.record("expected the sequence to throw")
    } catch let error as SentinelError {
      #expect(error == sentinel)
    }
    #expect(seen.isEmpty)
  }
}
