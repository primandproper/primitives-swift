import Foundation
import Observability
import Testing

@testable import Search

@Suite("Search configs")
struct SearchConfigTests {
  private let decoder = JSONDecoder()

  // MARK: - Text config

  @Test("TextSearchConfig decodes from {} to the noop-resolving default")
  func textEmptyDecode() throws {
    let config = try decoder.decode(TextSearchConfig.self, from: Data("{}".utf8))
    #expect(config.provider.isEmpty)
    #expect(config.resolvedProvider == nil)

    let searcher = try config.provideTextSearcher(pillars: .noop)
    #expect(searcher is NoopTextSearcher)
  }

  @Test("TextSearchConfig ignores dropped remote-backend keys")
  func textIgnoresDroppedKeys() throws {
    let json = """
      {"provider":"sqlite","elasticsearch":{"host":"x"},"algolia":{"appID":"y"},
      "circuitBreakerConfig":{"name":"z"}}
      """
    let config = try decoder.decode(TextSearchConfig.self, from: Data(json.utf8))
    #expect(config.resolvedProvider == .sqlite)
  }

  @Test("TextSearchConfig resolves sqlite (and the fts5 alias) to a live searcher")
  func textResolvesSqlite() async throws {
    for provider in ["sqlite", "FTS5", "  sqlite  "] {
      let config = TextSearchConfig(provider: provider)
      #expect(config.resolvedProvider == .sqlite)
      let searcher = try config.provideTextSearcher(pillars: .noop)
      #expect(searcher is SQLiteTextSearcher)
      try await searcher.index(TextDocument(id: "d1", content: "hello world"))
      #expect(try await searcher.search("hello").map(\.id) == ["d1"])
    }
  }

  @Test("TextSearchConfig round-trips through JSON")
  func textRoundTrip() throws {
    let original = TextSearchConfig(provider: "sqlite", indexName: "docs", path: "/tmp/x.db")
    let data = try JSONEncoder().encode(original)
    let decoded = try decoder.decode(TextSearchConfig.self, from: data)
    #expect(decoded == original)
  }

  // MARK: - Vector config

  @Test("VectorSearchConfig decodes from {} to the noop-resolving default")
  func vectorEmptyDecode() throws {
    let config = try decoder.decode(VectorSearchConfig.self, from: Data("{}".utf8))
    #expect(config.provider.isEmpty)
    #expect(config.dimensions == 0)
    #expect(config.resolvedProvider == nil)
    #expect(config.resolvedMetric == .cosine)

    let searcher = try config.provideVectorSearcher(pillars: .noop)
    #expect(searcher is NoopVectorSearcher)
  }

  @Test("VectorSearchConfig resolves memory (and the inmemory alias) to a live index")
  func vectorResolvesMemory() async throws {
    for provider in ["memory", "InMemory", " memory "] {
      let config = VectorSearchConfig(provider: provider, dimensions: 2, metric: "cosine")
      #expect(config.resolvedProvider == .inMemory)
      let searcher = try config.provideVectorSearcher(pillars: .noop)
      #expect(searcher is InMemoryVectorIndex)
      try await searcher.upsert(VectorRecord(id: "a", embedding: [1, 0]))
      #expect(try await searcher.query(VectorQuery(embedding: [1, 0], topK: 1)).map(\.id) == ["a"])
    }
  }

  @Test("VectorSearchConfig with the memory provider but a non-positive dimension throws")
  func vectorMemoryNeedsDimension() {
    let config = VectorSearchConfig(provider: "memory", dimensions: 0)
    #expect(throws: SearchError.invalidDimension(0)) {
      _ = try config.provideVectorSearcher(pillars: .noop)
    }
  }

  @Test("VectorSearchConfig resolves the metric, defaulting unknown to cosine")
  func vectorMetricResolution() {
    #expect(VectorSearchConfig(metric: "euclidean").resolvedMetric == .euclidean)
    #expect(VectorSearchConfig(metric: "DOT").resolvedMetric == .dot)
    #expect(VectorSearchConfig(metric: "nonsense").resolvedMetric == .cosine)
    #expect(VectorSearchConfig(metric: "").resolvedMetric == .cosine)
  }

  @Test("VectorSearchConfig ignores dropped remote-backend keys")
  func vectorIgnoresDroppedKeys() throws {
    let json = """
      {"provider":"memory","dimensions":4,"pgvector":{"dsn":"x"},"qdrant":{"url":"y"},
      "circuitBreakerConfig":{"name":"z"}}
      """
    let config = try decoder.decode(VectorSearchConfig.self, from: Data(json.utf8))
    #expect(config.resolvedProvider == .inMemory)
    #expect(config.dimensions == 4)
  }

  @Test("VectorSearchConfig round-trips through JSON")
  func vectorRoundTrip() throws {
    let original = VectorSearchConfig(provider: "memory", dimensions: 8, metric: "dot")
    let data = try JSONEncoder().encode(original)
    let decoded = try decoder.decode(VectorSearchConfig.self, from: data)
    #expect(decoded == original)
  }
}
