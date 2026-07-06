/// A single indexable text document. The concrete stand-in for Go's `value any` indexed payload and
/// `[T any]` returned type (see ``Search`` for why the generic collapses): an FTS5 index stores text, so
/// a document is its stable ``id`` plus the ``content`` that gets tokenized and matched.
public struct TextDocument: Sendable, Equatable, Codable {
  /// Stable identifier the caller keys its own model by. Re-indexing an existing ``id`` replaces it
  /// (upsert semantics), matching how Go's providers key on the document id.
  public var id: String
  /// The full text to index. Tokenized by FTS5 (`porter unicode61`) for matching; also stored verbatim
  /// so it can be returned on a hit.
  public var content: String

  public init(id: String, content: String) {
    self.id = id
    self.content = content
  }
}

/// A single hit returned from ``TextSearcher/search(_:limit:)``.
public struct TextSearchResult: Sendable, Equatable, Codable {
  /// The matched document's ``TextDocument/id``.
  public var id: String
  /// The matched document's stored ``TextDocument/content``.
  public var content: String
  /// Relevance score — **higher is more relevant**. Derived from FTS5's `bm25()` (negated, since SQLite's
  /// `bm25()` returns smaller values for better matches); results are always returned best-match-first, so
  /// a caller can rely on order without inspecting the number.
  public var score: Double

  public init(id: String, content: String, score: Double) {
    self.id = id
    self.content = content
    self.score = score
  }
}

/// The text-search seam, ported from platform-go's `textsearch.Index[T]` (`search/text/search.go`):
/// ```go
/// type Index[T any] interface {
///     Search(ctx, query string) (ids []*T, err error)  // IndexSearcher
///     Index(ctx, id string, value any) error            // IndexManager
///     Delete(ctx, id string) (err error)
///     Wipe(ctx) error
/// }
/// ```
/// `context.Context` becomes structured-concurrency cancellation; the `[T any]` payload collapses to a
/// concrete ``TextDocument``/``TextSearchResult`` (see ``Search``); Go's untyped `error` return becomes a
/// thrown ``SearchError``. ``search(_:limit:)`` adds a `limit` Go's signature lacks (Elasticsearch/Algolia
/// applied their own default page size server-side) so an on-device caller can bound the result set.
///
/// **Conformers:** ``SQLiteTextSearcher`` (native FTS5, the default), ``NoopTextSearcher`` (the safe
/// no-op), and actor ``TextSearcherMock`` (the test double).
public protocol TextSearcher: Sendable {
  /// Indexes (or re-indexes, upserting on ``TextDocument/id``) a single document. Go's `Index(ctx, id,
  /// value)`.
  func index(_ document: TextDocument) async throws

  /// Returns the best matches for `query`, most-relevant first, capped at `limit`. Go's `Search(ctx,
  /// query)`. An empty/whitespace query yields no results rather than erroring.
  func search(_ query: String, limit: Int) async throws -> [TextSearchResult]

  /// Removes the document with `id`. A missing `id` is a silent no-op, matching Go's providers. Go's
  /// `Delete(ctx, id)`.
  func delete(id: String) async throws

  /// Removes every document, leaving the index itself in place. Go's `Wipe(ctx)`.
  func wipe() async throws
}

extension TextSearcher {
  /// Indexes a batch of documents in order. A pure convenience over ``index(_:)`` — the native FTS5
  /// backend has no faster bulk path worth a distinct requirement, matching how Go callers index one
  /// document at a time.
  public func index(_ documents: [TextDocument]) async throws {
    for document in documents {
      try Task.checkCancellation()
      try await index(document)
    }
  }

  /// ``search(_:limit:)`` with a default `limit` of 20 — a sensible on-device page size.
  public func search(_ query: String) async throws -> [TextSearchResult] {
    try await search(query, limit: 20)
  }
}
