import Embeddings
import Testing

@testable import Search

@Suite("InMemoryVectorIndex")
struct VectorSearchTests {
  @Test("cosine similarity is correct on known vectors and orders results best-first")
  func cosineKnownVectors() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2, metric: .cosine)
    try await index.upsert([
      VectorRecord(id: "same", embedding: [1, 0]),
      VectorRecord(id: "orthogonal", embedding: [0, 1]),
      VectorRecord(id: "opposite", embedding: [-1, 0]),
    ])

    let results = try await index.query(VectorQuery(embedding: [1, 0], topK: 3))

    #expect(results.map(\.id) == ["same", "orthogonal", "opposite"])
    #expect(abs(results[0].score - 1) < 1e-6)
    #expect(abs(results[1].score - 0) < 1e-6)
    #expect(abs(results[2].score - -1) < 1e-6)
  }

  @Test("cosine handles a non-trivial angle (45°) to the expected value")
  func cosineFortyFiveDegrees() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    try await index.upsert(VectorRecord(id: "diag", embedding: [1, 1]))

    let results = try await index.query(VectorQuery(embedding: [1, 0], topK: 1))

    #expect(results.count == 1)
    #expect(abs(results[0].score - Float(1.0 / 2.0.squareRoot())) < 1e-6)
  }

  @Test("top-K bounds and orders the result set; topK <= 0 returns all")
  func topKOrdering() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    try await index.upsert([
      VectorRecord(id: "a", embedding: [1, 0]),
      VectorRecord(id: "b", embedding: [0.9, 0.1]),
      VectorRecord(id: "c", embedding: [0.1, 0.9]),
      VectorRecord(id: "d", embedding: [0, 1]),
    ])

    let top2 = try await index.query(VectorQuery(embedding: [1, 0], topK: 2))
    #expect(top2.map(\.id) == ["a", "b"])

    let all = try await index.query(VectorQuery(embedding: [1, 0], topK: 0))
    #expect(all.count == 4)
    // Scores descend (best-first).
    #expect(all[0].score >= all[1].score)
    #expect(all[1].score >= all[2].score)
    #expect(all[2].score >= all[3].score)
  }

  @Test("dot and euclidean metrics both rank the nearest vector first")
  func alternativeMetrics() async throws {
    let dotIndex = try InMemoryVectorIndex(dimensions: 2, metric: .dot)
    try await dotIndex.upsert([
      VectorRecord(id: "big", embedding: [2, 0]),
      VectorRecord(id: "small", embedding: [1, 0]),
    ])
    let dotResults = try await dotIndex.query(VectorQuery(embedding: [1, 0], topK: 2))
    #expect(dotResults.map(\.id) == ["big", "small"])
    #expect(abs(dotResults[0].score - 2) < 1e-6)

    let euclideanIndex = try InMemoryVectorIndex(dimensions: 2, metric: .euclidean)
    try await euclideanIndex.upsert([
      VectorRecord(id: "near", embedding: [1, 0]),
      VectorRecord(id: "far", embedding: [5, 5]),
    ])
    let euclideanResults = try await euclideanIndex.query(
      VectorQuery(embedding: [1, 0], topK: 2))
    #expect(euclideanResults.map(\.id) == ["near", "far"])
    // near is exact → distance 0 → score 0.
    #expect(abs(euclideanResults[0].score - 0) < 1e-6)
    #expect(euclideanResults[1].score < 0)
  }

  @Test("upsert replaces an existing id and metadata rides along on hits")
  func upsertReplacesAndCarriesMetadata() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    try await index.upsert(VectorRecord(id: "x", embedding: [1, 0], metadata: ["v": "1"]))
    try await index.upsert(VectorRecord(id: "x", embedding: [0, 1], metadata: ["v": "2"]))

    #expect(await index.count == 1)
    let results = try await index.query(VectorQuery(embedding: [0, 1], topK: 1))
    #expect(results[0].id == "x")
    #expect(results[0].metadata == ["v": "2"])
  }

  @Test("delete removes records; a missing id is a silent no-op")
  func deleteRemoves() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    try await index.upsert([
      VectorRecord(id: "a", embedding: [1, 0]),
      VectorRecord(id: "b", embedding: [0, 1]),
    ])
    try await index.delete(ids: ["a", "missing"])

    #expect(await index.count == 1)
    let results = try await index.query(VectorQuery(embedding: [1, 0], topK: 10))
    #expect(results.map(\.id) == ["b"])
  }

  @Test("wipe empties the index")
  func wipeEmpties() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    try await index.upsert(VectorRecord(id: "a", embedding: [1, 0]))
    try await index.wipe()

    #expect(await index.count == 0)
    let results = try await index.query(VectorQuery(embedding: [1, 0], topK: 10))
    #expect(results.isEmpty)
  }

  @Test("a dimension mismatch on upsert throws")
  func dimensionMismatchUpsert() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    await #expect(throws: SearchError.dimensionMismatch(expected: 2, actual: 3)) {
      try await index.upsert(VectorRecord(id: "x", embedding: [1, 2, 3]))
    }
  }

  @Test("a dimension mismatch on query throws")
  func dimensionMismatchQuery() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    await #expect(throws: SearchError.dimensionMismatch(expected: 2, actual: 1)) {
      _ = try await index.query(VectorQuery(embedding: [1], topK: 1))
    }
  }

  @Test("an empty embedding throws emptyEmbedding")
  func emptyEmbedding() async throws {
    let index = try InMemoryVectorIndex(dimensions: 2)
    await #expect(throws: SearchError.emptyEmbedding) {
      _ = try await index.query(VectorQuery(embedding: [], topK: 1))
    }
  }

  @Test("a non-positive index dimension is rejected at construction")
  func invalidDimension() {
    #expect(throws: SearchError.invalidDimension(0)) {
      _ = try InMemoryVectorIndex(dimensions: 0)
    }
  }

  @Test("the Embedder-backed convenience path indexes and queries by text")
  func embedderConvenience() async throws {
    // A deterministic mock embedder: known words map to fixed 2-D vectors.
    let vectors: [String: [Float]] = [
      "cat": [1, 0],
      "kitten": [0.95, 0.31],
      "dog": [0, 1],
    ]
    let embedder = EmbedderMock(dimensions: 2) { text in vectors[text] ?? [0, 0] }
    let index = try InMemoryVectorIndex(dimensions: 2)

    try await index.upsert(id: "1", text: "cat", metadata: ["kind": "feline"], using: embedder)
    try await index.upsert(id: "2", text: "dog", using: embedder)

    let results = try await index.query(text: "kitten", topK: 2, using: embedder)
    #expect(results.first?.id == "1")
    #expect(results.first?.metadata == ["kind": "feline"])
  }

  @Test("the static score function computes cosine, dot, and euclidean directly")
  func staticScore() {
    #expect(abs(InMemoryVectorIndex.score([1, 0], [1, 0], metric: .cosine) - 1) < 1e-6)
    #expect(abs(InMemoryVectorIndex.score([1, 2], [3, 4], metric: .dot) - 11) < 1e-6)
    #expect(abs(InMemoryVectorIndex.score([0, 0], [3, 4], metric: .euclidean) - -5) < 1e-6)
    // Cosine with a zero-magnitude vector avoids a divide-by-zero, returning 0.
    #expect(InMemoryVectorIndex.score([0, 0], [1, 0], metric: .cosine) == 0)
  }
}
