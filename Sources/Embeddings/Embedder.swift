/// The embedding seam, ported from platform-go's `embeddings.Embedder` interface (`embeddings.go`).
///
/// Go's whole public surface is one method:
/// ```go
/// type Embedder interface {
///     GenerateEmbedding(ctx context.Context, input *Input) (*Embedding, error)
/// }
/// ```
/// This is the simplified Swift analogue that the sibling `Search` module (PORT-08) consumes directly:
/// `context.Context` becomes structured-concurrency cancellation, `*Input` collapses to a bare `String`
/// (Go's `Input.Model` per-call override is dropped — a conformer is configured with one model at
/// construction, matching how ``dimensions`` is fixed per instance too), and `(*Embedding, error)`
/// becomes a non-optional `[Float]` return that `throws` — Go's provenance fields (`SourceText`, `Model`,
/// `Provider`, `GeneratedAt`) are dropped from the return value since neither this platform nor Search
/// persists them; `Dimensions` survives, promoted to ``dimensions``, a property of the embedder itself
/// rather than a field on each result, so a caller can size a vector index before embedding anything.
///
/// **Conformers:** ``OnDeviceEmbedder`` (native, offline, no Go counterpart), ``OpenAIEmbedder`` (a live
/// HTTP backend mirroring `Sources/LLM`'s pattern), ``NoopEmbedder`` (the safe default), and actor
/// ``EmbedderMock`` (the test double). See ``Embeddings`` for the full port rationale.
public protocol Embedder: Sendable {
  /// The dimensionality of the vectors ``embed(_:)`` produces. Fixed for the lifetime of the instance —
  /// e.g. resolved from the on-device model's own dimension, or from the configured OpenAI model's known
  /// output width — so a caller (Search, building a vector index) can size storage before embedding
  /// anything, without an `async` round trip.
  var dimensions: Int { get }

  /// Embeds a single piece of text, returning its vector representation. Throws rather than returning an
  /// error value, the structured-concurrency analogue of Go's `(*Embedding, error)`.
  func embed(_ text: String) async throws -> [Float]

  /// Embeds a batch of texts, in order. The default implementation (see the extension below) simply
  /// loops ``embed(_:)`` sequentially — Go's interface has no batch call either, so this is a pure
  /// convenience over the single-item seam, not a behavioral divergence. A conformer whose backend
  /// supports a genuine batch request (nothing in this port's kept backends does; OpenAI's own API would,
  /// but Go never exercises it) may override this for efficiency without changing the public contract.
  func embed(_ texts: [String]) async throws -> [[Float]]
}

extension Embedder {
  public func embed(_ texts: [String]) async throws -> [[Float]] {
    var results: [[Float]] = []
    results.reserveCapacity(texts.count)
    for text in texts {
      try Task.checkCancellation()
      results.append(try await embed(text))
    }
    return results
  }
}
