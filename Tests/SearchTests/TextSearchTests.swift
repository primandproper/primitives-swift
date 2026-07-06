import Testing

@testable import Search

@Suite("SQLiteTextSearcher (FTS5)")
struct TextSearchTests {
  private func makeIndex() throws -> SQLiteTextSearcher {
    try SQLiteTextSearcher()
  }

  @Test("indexing then searching returns the matching document with its content")
  func indexAndSearch() async throws {
    let index = try makeIndex()
    try await index.index(TextDocument(id: "d1", content: "the quick brown fox"))

    let results = try await index.search("fox")

    #expect(results.count == 1)
    #expect(results[0].id == "d1")
    #expect(results[0].content == "the quick brown fox")
  }

  @Test("bm25 ranking puts the document matching more query terms first")
  func ranking() async throws {
    let index = try makeIndex()
    try await index.index([
      TextDocument(id: "d1", content: "the quick brown fox"),
      TextDocument(id: "d2", content: "the lazy dog"),
      TextDocument(id: "d3", content: "quick brown dog"),
    ])

    let results = try await index.search("quick brown fox")

    // d1 matches all three terms, d3 matches two, d2 matches none.
    #expect(results.map(\.id) == ["d1", "d3"])
    #expect(results[0].score >= results[1].score)
  }

  @Test("re-indexing the same id updates its content in place")
  func updateInPlace() async throws {
    let index = try makeIndex()
    try await index.index(TextDocument(id: "d1", content: "quick brown fox"))
    try await index.index(TextDocument(id: "d1", content: "sleepy tortoise"))

    #expect(await index.count == 1)
    #expect(try await index.search("fox").isEmpty)
    let results = try await index.search("tortoise")
    #expect(results.map(\.id) == ["d1"])
  }

  @Test("delete removes a document; a missing id is a silent no-op")
  func delete() async throws {
    let index = try makeIndex()
    try await index.index([
      TextDocument(id: "d1", content: "quick brown fox"),
      TextDocument(id: "d2", content: "lazy dog"),
    ])

    try await index.delete(id: "d1")
    try await index.delete(id: "missing")

    #expect(await index.count == 1)
    #expect(try await index.search("fox").isEmpty)
    #expect(try await index.search("dog").map(\.id) == ["d2"])
  }

  @Test("wipe removes every document")
  func wipe() async throws {
    let index = try makeIndex()
    try await index.index([
      TextDocument(id: "d1", content: "quick brown fox"),
      TextDocument(id: "d2", content: "lazy dog"),
    ])

    try await index.wipe()

    #expect(await index.count == 0)
    #expect(try await index.search("fox").isEmpty)
  }

  @Test("limit bounds the number of hits")
  func limit() async throws {
    let index = try makeIndex()
    for i in 0..<5 {
      try await index.index(TextDocument(id: "d\(i)", content: "shared term here"))
    }

    let results = try await index.search("term", limit: 3)
    #expect(results.count == 3)
  }

  @Test("stemming matches inflected forms (porter tokenizer)")
  func stemming() async throws {
    let index = try makeIndex()
    try await index.index(TextDocument(id: "d1", content: "the foxes were running quickly"))

    // "running" stems to "run", "foxes" to "fox".
    #expect(try await index.search("run").map(\.id) == ["d1"])
    #expect(try await index.search("fox").map(\.id) == ["d1"])
  }

  @Test("an empty or punctuation-only query yields no results without erroring")
  func emptyQuery() async throws {
    let index = try makeIndex()
    try await index.index(TextDocument(id: "d1", content: "hello world"))

    #expect(try await index.search("").isEmpty)
    #expect(try await index.search("   ").isEmpty)
    #expect(try await index.search("!!! ???").isEmpty)
  }

  @Test("a query containing FTS5 special characters is treated as literal terms")
  func specialCharactersAreSafe() async throws {
    let index = try makeIndex()
    try await index.index(TextDocument(id: "d1", content: "safe content"))

    // Quotes / operators must not blow up the MATCH parse.
    let results = try await index.search("\"safe\" OR (content*)")
    #expect(results.map(\.id) == ["d1"])
  }

  @Test("an invalid index name is rejected at construction")
  func invalidIndexName() {
    #expect(throws: SearchError.invalidConfig("invalid index name: bad-name")) {
      _ = try SQLiteTextSearcher(indexName: "bad-name")
    }
    #expect(throws: (any Error).self) {
      _ = try SQLiteTextSearcher(indexName: "1leading_digit")
    }
  }

  @Test("matchExpression ORs alphanumeric terms and drops empties")
  func matchExpressionShape() {
    #expect(
      SQLiteTextSearcher.matchExpression(for: "quick brown") == "\"quick\" OR \"brown\"")
    #expect(SQLiteTextSearcher.matchExpression(for: "  ") == nil)
    #expect(SQLiteTextSearcher.matchExpression(for: "one") == "\"one\"")
  }

  @Test("isValidIdentifier accepts valid identifiers and rejects the rest")
  func identifierValidation() {
    #expect(SQLiteTextSearcher.isValidIdentifier("search_documents"))
    #expect(SQLiteTextSearcher.isValidIdentifier("_x1"))
    #expect(!SQLiteTextSearcher.isValidIdentifier("1abc"))
    #expect(!SQLiteTextSearcher.isValidIdentifier("has space"))
    #expect(!SQLiteTextSearcher.isValidIdentifier(""))
    #expect(!SQLiteTextSearcher.isValidIdentifier("drop;table"))
  }
}
