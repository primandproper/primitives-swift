import Embeddings

/// The nearest-neighbor scoring function, ported from platform-go's `vectorsearch.DistanceMetric`
/// (`search/vector/vector.go`) — same raw string values (`cosine`, `dot`, `euclidean`).
///
/// ``InMemoryVectorIndex`` implements all three. For a uniform API the public
/// ``VectorSearchResult/score`` is always **higher-is-better** (results come back best-match-first
/// regardless of metric): cosine and dot use the raw similarity, and euclidean uses the *negated* L2
/// distance — a deliberate deviation from Go's `QueryResult.Distance`, which surfaces the raw metric value
/// (for cosine, a `[0, 2]` distance where *lower* is better). See ``VectorSearchResult``.
public enum VectorDistanceMetric: String, Codable, Sendable, CaseIterable {
  /// Cosine similarity: `dot(a,b) / (‖a‖·‖b‖)`, in `[-1, 1]`, higher is more similar. The default and the
  /// metric the PORT-08 spec calls for.
  case cosine
  /// Raw dot product, unbounded, higher is more similar.
  case dot = "dot"
  /// Euclidean (L2) distance. Scored as its negation so higher still means more similar.
  case euclidean
}

/// A single indexable point. The concrete stand-in for Go's `vectorsearch.Vector[T]` (its `*T` metadata
/// generic collapses to a string→string ``metadata`` map — enough to carry a payload back on a hit without
/// dragging a generic through the seam; see ``Search``).
public struct VectorRecord: Sendable, Equatable {
  /// Stable identifier. Upserting an existing ``id`` replaces its vector and metadata.
  public var id: String
  /// The point's vector. Must match the index's configured dimension.
  public var embedding: [Float]
  /// Opaque caller payload returned verbatim on a hit.
  public var metadata: [String: String]

  public init(id: String, embedding: [Float], metadata: [String: String] = [:]) {
    self.id = id
    self.embedding = embedding
    self.metadata = metadata
  }
}

/// A top-K nearest-neighbor request, ported from Go's `vectorsearch.QueryRequest`. Go's opaque per-provider
/// `Filter any` is dropped (the dropped pgvector/qdrant backends were its only consumers — see ``Search``).
public struct VectorQuery: Sendable, Equatable {
  /// The query vector. Must match the index dimension.
  public var embedding: [Float]
  /// Number of results to return. `<= 0` returns every record, ranked.
  public var topK: Int

  public init(embedding: [Float], topK: Int = 10) {
    self.embedding = embedding
    self.topK = topK
  }
}

/// A single hit from ``VectorSearcher/query(_:)``, ported from Go's `vectorsearch.QueryResult[T]`.
public struct VectorSearchResult: Sendable, Equatable {
  /// The matched ``VectorRecord/id``.
  public var id: String
  /// Similarity score — **higher is more similar**, for every ``VectorDistanceMetric`` (euclidean is
  /// negated to keep the direction uniform; see that type). Results are ordered best-first.
  public var score: Float
  /// The matched record's ``VectorRecord/metadata``.
  public var metadata: [String: String]

  public init(id: String, score: Float, metadata: [String: String] = [:]) {
    self.id = id
    self.score = score
    self.metadata = metadata
  }
}

/// The vector-search seam, ported from platform-go's `vectorsearch.Index[T]` (`search/vector/vector.go`):
/// ```go
/// type Index[T any] interface {
///     Upsert(ctx, vectors ...Vector[T]) error       // IndexWriter
///     Delete(ctx, ids ...string) error
///     Wipe(ctx) error
///     Query(ctx, req QueryRequest) ([]QueryResult[T], error)  // IndexSearcher
/// }
/// ```
/// `context.Context` becomes structured-concurrency cancellation; the `[T any]` metadata generic collapses
/// to a `[String: String]` map on ``VectorRecord``/``VectorSearchResult``; the variadic `...Vector`/`...string`
/// become `[VectorRecord]`/`[String]`; Go's untyped `error` becomes a thrown ``SearchError``.
///
/// The core methods take **pre-computed `[Float]` vectors**. A text→vector convenience path
/// (``upsert(id:text:metadata:using:)`` / ``query(text:topK:using:)``) is layered on as protocol
/// extensions that consume the `Embeddings` module's `Embedder` seam, so a caller can hand the index raw
/// text without wiring the embed step — while any conformer only implements the vector-level core.
///
/// **Conformers:** ``InMemoryVectorIndex`` (native brute-force, the default), ``NoopVectorSearcher`` (the
/// safe no-op), and actor ``VectorSearcherMock`` (the test double).
public protocol VectorSearcher: Sendable {
  /// Inserts or replaces records keyed by ``VectorRecord/id``. Go's `Upsert`. Throws
  /// ``SearchError/emptyEmbedding`` or ``SearchError/dimensionMismatch(expected:actual:)`` for a bad
  /// vector.
  func upsert(_ records: [VectorRecord]) async throws

  /// Removes records by id. Missing ids are ignored. Go's `Delete`.
  func delete(ids: [String]) async throws

  /// Removes every record, leaving the index in place. Go's `Wipe`.
  func wipe() async throws

  /// Returns the top-`request.topK` nearest neighbors of `request.embedding`, most-similar first. Go's
  /// `Query`. Throws ``SearchError/emptyEmbedding`` or ``SearchError/dimensionMismatch(expected:actual:)``
  /// for a bad query vector.
  func query(_ request: VectorQuery) async throws -> [VectorSearchResult]
}

extension VectorSearcher {
  /// Upserts a single record. Convenience over ``upsert(_:)``.
  public func upsert(_ record: VectorRecord) async throws {
    try await upsert([record])
  }

  /// Deletes a single id. Convenience over ``delete(ids:)``.
  public func delete(id: String) async throws {
    try await delete(ids: [id])
  }

  /// Embeds `text` via `embedder`, then upserts it as a record under `id`. The text→vector convenience
  /// path: the core index still stores a plain `[Float]`, this just spares the caller the embed call.
  public func upsert(
    id: String,
    text: String,
    metadata: [String: String] = [:],
    using embedder: any Embedder
  ) async throws {
    let embedding = try await embedder.embed(text)
    try await upsert([VectorRecord(id: id, embedding: embedding, metadata: metadata)])
  }

  /// Embeds `text` via `embedder`, then queries for its nearest neighbors. The read-side counterpart of
  /// ``upsert(id:text:metadata:using:)``.
  public func query(
    text: String,
    topK: Int = 10,
    using embedder: any Embedder
  ) async throws -> [VectorSearchResult] {
    let embedding = try await embedder.embed(text)
    return try await query(VectorQuery(embedding: embedding, topK: topK))
  }
}
