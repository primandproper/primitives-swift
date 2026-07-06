import Testing

@testable import Files

@Suite("sliceLines(from:offset:count:) — windowed reads")
struct SliceLinesTests {
  private static let ten = "l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\n"

  private func slice(_ string: String, offset: Int, count: Int) async throws -> [String] {
    try await sliceLines(from: ThrowingByteSequence(string), offset: offset, count: count)
  }

  @Test("returns the window after the offset")
  func windowAfterOffset() async throws {
    #expect(try await slice(Self.ten, offset: 8, count: 10) == ["l8", "l9"])
  }

  @Test("returns a short slice when fewer than count remain")
  func shortSlice() async throws {
    #expect(try await slice(Self.ten, offset: 3, count: 4) == ["l3", "l4", "l5", "l6"])
  }

  @Test("offset at or past EOF throws offsetBeyondEOF")
  func offsetPastEOF() async throws {
    await #expect(throws: FilesError.offsetBeyondEOF) {
      _ = try await self.slice("a\nb\nc\n", offset: 8, count: 10)
    }
  }

  @Test("offset exactly equal to line count is beyond EOF")
  func offsetExactlyAtEOF() async throws {
    await #expect(throws: FilesError.offsetBeyondEOF) {
      _ = try await self.slice("a\nb\nc\n", offset: 3, count: 1)
    }
  }

  @Test("count of zero returns an empty slice without reading")
  func zeroCount() async throws {
    #expect(try await slice(Self.ten, offset: 2, count: 0) == [])
  }

  @Test("negative offset is rejected")
  func negativeOffset() async throws {
    await #expect(throws: FilesError.negativeOffset) {
      _ = try await self.slice(Self.ten, offset: -1, count: 3)
    }
  }

  @Test("negative count is rejected")
  func negativeCount() async throws {
    await #expect(throws: FilesError.negativeCount) {
      _ = try await self.slice(Self.ten, offset: 0, count: -1)
    }
  }
}
