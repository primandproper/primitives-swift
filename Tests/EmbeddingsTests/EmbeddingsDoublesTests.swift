import Foundation
import Testing

@testable import Embeddings

@Suite("Embeddings doubles")
struct EmbeddingsDoublesTests {
  @Test("NoopEmbedder always yields an empty vector and zero dimensions")
  func noopEmpty() async throws {
    let embedder: any Embedder = NoopEmbedder()
    #expect(embedder.dimensions == 0)
    let vector = try await embedder.embed("hello world")
    #expect(vector.isEmpty)
  }

  @Test("EmbedderMock with no handler returns an empty vector and records the call")
  func mockUnsetRecords() async throws {
    let mock = EmbedderMock(dimensions: 3)
    #expect(mock.dimensions == 3)

    let vector = try await mock.embed("hi")

    #expect(vector.isEmpty)
    let calls = await mock.embedCalls
    #expect(calls == ["hi"])
  }

  @Test("the mock runs its constructor-supplied handler")
  func mockHandlerFromInit() async throws {
    let mock = EmbedderMock(dimensions: 2) { text in
      text == "hi" ? [1, 2] : [0, 0]
    }

    let vector = try await mock.embed("hi")

    #expect(vector == [1, 2])
  }

  @Test("setEmbedHandler scripts the return post-init (can't assign the var cross-actor)")
  func mockSetHandler() async throws {
    let mock = EmbedderMock()
    await mock.setEmbedHandler { text in [Float(text.count)] }

    let vector = try await mock.embed("abcd")

    #expect(vector == [4])
  }

  @Test("a throwing handler propagates its typed EmbeddingsError")
  func mockThrows() async throws {
    let mock = EmbedderMock(embedHandler: { _ in throw EmbeddingsError.authentication })
    await #expect(throws: EmbeddingsError.authentication) {
      _ = try await mock.embed("x")
    }
  }

  @Test("the default batch embed extension loops embed(_:) in order and records each call")
  func defaultBatchLoopsInOrder() async throws {
    let mock = EmbedderMock { text in [Float(text.count)] }

    let vectors = try await mock.embed(["a", "bb", "ccc"])

    #expect(vectors == [[1], [2], [3]])
    let calls = await mock.embedCalls
    #expect(calls == ["a", "bb", "ccc"])
  }
}
