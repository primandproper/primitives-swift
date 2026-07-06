/// An in-memory `AsyncSequence<UInt8>` test double, the Swift analogue of platform-go's test-only
/// `errReader`/`partialErrReader` (`lines_test.go`): yields `data`, then — if `error` is set — throws it
/// instead of completing cleanly. Lets the line/chunk/slice tests exercise a mid-stream read failure
/// without a real file.
struct ThrowingByteSequence: AsyncSequence, Sendable {
  typealias Element = UInt8

  let data: [UInt8]
  let error: (any Error)?

  init(_ string: String, thenThrow error: (any Error)? = nil) {
    self.data = Array(string.utf8)
    self.error = error
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(data: data, error: error)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    let data: [UInt8]
    let error: (any Error)?
    var index = 0

    mutating func next() async throws -> UInt8? {
      if index < data.count {
        defer { index += 1 }
        return data[index]
      }
      if let error {
        throw error
      }
      return nil
    }
  }
}

struct SentinelError: Error, Equatable {
  let id: String
}
