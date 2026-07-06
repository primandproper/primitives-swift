import Testing

@testable import Search

@Suite("Search doubles")
struct SearchDoublesTests {
  // MARK: - Text

  @Test("NoopTextSearcher yields no results and silently accepts writes")
  func noopText() async throws {
    let searcher: any TextSearcher = NoopTextSearcher()
    try await searcher.index(TextDocument(id: "x", content: "hello"))
    try await searcher.delete(id: "x")
    try await searcher.wipe()
    #expect(try await searcher.search("hello").isEmpty)
  }

  @Test("TextSearcherMock records calls and returns empty by default")
  func textMockRecords() async throws {
    let mock = TextSearcherMock()
    try await mock.index(TextDocument(id: "d1", content: "a"))
    _ = try await mock.search("q", limit: 5)
    try await mock.delete(id: "d1")
    try await mock.wipe()

    #expect(await mock.indexCalls == [TextDocument(id: "d1", content: "a")])
    #expect(await mock.searchCalls.map(\.query) == ["q"])
    #expect(await mock.searchCalls.map(\.limit) == [5])
    #expect(await mock.deleteCalls == ["d1"])
    #expect(await mock.wipeCalls == 1)
  }

  @Test("TextSearcherMock runs a scripted search handler set post-init")
  func textMockHandler() async throws {
    let mock = TextSearcherMock()
    await mock.setSearchHandler { query, _ in
      [TextSearchResult(id: query, content: "hit", score: 1)]
    }

    let results = try await mock.search("abc", limit: 10)
    #expect(results == [TextSearchResult(id: "abc", content: "hit", score: 1)])
  }

  @Test("TextSearcherMock propagates a throwing handler")
  func textMockThrows() async throws {
    let mock = TextSearcherMock(indexHandler: { _ in throw SearchError.backend("boom") })
    await #expect(throws: SearchError.backend("boom")) {
      try await mock.index(TextDocument(id: "x", content: "y"))
    }
  }

  // MARK: - Vector

  @Test("NoopVectorSearcher yields no results and silently accepts writes")
  func noopVector() async throws {
    let searcher: any VectorSearcher = NoopVectorSearcher()
    try await searcher.upsert(VectorRecord(id: "x", embedding: [1, 2]))
    try await searcher.delete(id: "x")
    try await searcher.wipe()
    #expect(try await searcher.query(VectorQuery(embedding: [1, 2], topK: 3)).isEmpty)
  }

  @Test("VectorSearcherMock records calls and returns empty by default")
  func vectorMockRecords() async throws {
    let mock = VectorSearcherMock()
    try await mock.upsert([VectorRecord(id: "a", embedding: [1, 0])])
    _ = try await mock.query(VectorQuery(embedding: [1, 0], topK: 2))
    try await mock.delete(ids: ["a"])
    try await mock.wipe()

    #expect(await mock.upsertCalls.count == 1)
    #expect(await mock.upsertCalls[0] == [VectorRecord(id: "a", embedding: [1, 0])])
    #expect(await mock.queryCalls == [VectorQuery(embedding: [1, 0], topK: 2)])
    #expect(await mock.deleteCalls == [["a"]])
    #expect(await mock.wipeCalls == 1)
  }

  @Test("VectorSearcherMock runs a scripted query handler set post-init")
  func vectorMockHandler() async throws {
    let mock = VectorSearcherMock()
    await mock.setQueryHandler { request in
      [VectorSearchResult(id: "hit", score: request.score(), metadata: [:])]
    }

    let results = try await mock.query(VectorQuery(embedding: [1, 0], topK: 7))
    #expect(results == [VectorSearchResult(id: "hit", score: 7, metadata: [:])])
  }
}

extension VectorQuery {
  /// Tiny helper so the mock-handler test can echo a request-derived score.
  fileprivate func score() -> Float { Float(topK) }
}
