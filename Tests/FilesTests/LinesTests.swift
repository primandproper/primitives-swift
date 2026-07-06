import Testing

@testable import Files

@Suite("lines(from:)")
struct LinesTests {
  private func collect(_ string: String, thenThrow error: (any Error)? = nil) async throws
    -> [String]
  {
    var out: [String] = []
    for try await line in lines(from: ThrowingByteSequence(string, thenThrow: error)) {
      out.append(line)
    }
    return out
  }

  @Test("yields each line without the trailing newline")
  func trailingNewlineTrimmed() async throws {
    #expect(try await collect("a\nb\nc\n") == ["a", "b", "c"])
  }

  @Test("handles CRLF line endings")
  func crlf() async throws {
    #expect(try await collect("a\r\nb\r\n") == ["a", "b"])
  }

  @Test("preserves blank lines")
  func blankLines() async throws {
    #expect(try await collect("a\n\nb\n") == ["a", "", "b"])
  }

  @Test("yields an unterminated final line")
  func unterminatedFinalLine() async throws {
    #expect(try await collect("a\nb") == ["a", "b"])
  }

  @Test("empty input yields nothing")
  func emptyInput() async throws {
    #expect(try await collect("") == [])
  }

  @Test("surfaces a read error")
  func readError() async throws {
    let sentinel = SentinelError(id: "boom")
    await #expect(throws: sentinel) {
      _ = try await collect("a\nb\n", thenThrow: sentinel)
    }
  }

  @Test("does not yield a truncated fragment as a good line on a read error")
  func truncatedFragmentDiscardedOnError() async throws {
    let sentinel = SentinelError(id: "boom")
    var seen: [String] = []
    do {
      for try await line in lines(
        from: ThrowingByteSequence("partial-no-newline", thenThrow: sentinel))
      {
        seen.append(line)
      }
      Issue.record("expected the sequence to throw")
    } catch let error as SentinelError {
      #expect(error == sentinel)
    }
    #expect(seen.isEmpty)
  }
}
