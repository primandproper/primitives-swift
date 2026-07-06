/// # Search
///
/// Ported from platform-go's `search` package (`search/text` + `search/vector`) — the client-relevant
/// slice, per the iOS-only scope of this port (see `PORTING.md`). The Go package is two parallel
/// protocol families, and this module keeps both:
///
/// ## Text search (`search/text`, package `textsearch`)
///
/// Go's `textsearch.Index[T]` is `Index(ctx, id, value any)` + `Delete(ctx, id)` + `Wipe(ctx)` +
/// `Search(ctx, query) ([]*T, error)`, dispatched by `textsearchcfg.Config` to an **Elasticsearch** or
/// **Algolia** backend (or a noop). Both backends are remote HTTP services with no iOS-native analogue,
/// so per the settled port architecture (thin/native/no-dependency, drop server backends) **both are
/// dropped**. What ships instead is ``SQLiteTextSearcher`` — a **new**, iOS-native full-text index built
/// on SQLite's **FTS5** virtual-table module (through the system `SQLite3` C library, so it is fully
/// unit-testable in-process against an in-memory database), plus ``NoopTextSearcher`` and actor
/// ``TextSearcherMock``. The seam (``TextSearcher``) is preserved so a remote adapter (wrapping the
/// dropped Elasticsearch/Algolia clients, or CoreSpotlight) can conform later.
///
/// Go's `Index[T any]` generic over an arbitrary stored/returned payload type collapses to a concrete
/// ``TextDocument`` (`id` + indexed `content`) and ``TextSearchResult` — the same simplification
/// `Embeddings` made when it collapsed Go's `*Input` to a bare `String`: an FTS5 index stores text, and a
/// mobile caller keys results back to its own model by `id`.
///
/// ## Vector search (`search/vector`, package `vectorsearch`)
///
/// Go's `vectorsearch.Index[T]` is `Upsert` + `Delete` + `Wipe` + `Query(topK)`, dispatched by
/// `vectorsearchcfg.Config` to a **pgvector** (Postgres extension) or **Qdrant** (a vector-DB server)
/// backend. Both are server-side stores with no iOS analogue, so **both are dropped** and replaced by
/// ``InMemoryVectorIndex`` — brute-force nearest-neighbor over `[Float]` vectors held in an actor, which
/// is entirely adequate on-device (a phone's working set is thousands, not billions, of vectors). It
/// implements all three of Go's ``VectorDistanceMetric`` scoring functions (cosine, dot, euclidean),
/// defaulting to cosine. ``NoopVectorSearcher`` and actor ``VectorSearcherMock`` round out the seam.
///
/// The core index accepts **pre-computed `[Float]` vectors** directly (``VectorSearcher/upsert(_:)-…`` /
/// ``VectorSearcher/query(_:)``); a text→vector convenience path (``VectorSearcher/upsert(id:text:metadata:using:)``
/// and ``VectorSearcher/query(text:topK:using:)``) layers on top by consuming the `Embeddings` module's
/// `Embedder` seam, so a caller can hand the index raw text without wiring the embed step themselves.
///
/// ## What is dropped
///
/// * **Elasticsearch / Algolia** (text) and **pgvector / Qdrant** (vector) backends — all remote; the
///   protocol seams remain for a future adapter.
/// * The `samber/do` DI registration and the `env:`-tagged config plumbing — replaced by plain
///   constructor injection and lenient `Codable` configs, as everywhere in this port.
/// * Go's `circuitbreakingcfg.Config` field on both dispatch configs — the native backends make no remote
///   call, so there is nothing to break. A Go-authored payload's `circuitBreakerConfig` key simply
///   decode-and-ignores (`Codable` skips unrecognized keys), so wire compatibility is preserved.
/// * Go's `[T any]` payload generics — collapsed to concrete document/record types (see above).
///
/// Observability threads through an injected ``Observability/Pillars`` (the SVC-10 rule): every
/// side-effecting operation opens a span and emits request/error counters plus a latency histogram, the
/// same convention `Sources/Cache`'s `InMemoryCache` follows.
public enum Search {}
