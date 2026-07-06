/// A no-op ``Embedder``, ported from platform-go's `embeddings/noop`. The safe default when no provider
/// is configured (or an unrecognized one is): every call returns an empty vector rather than leaving
/// callers nil-checking an embedder that may not exist. Mirrors Go's `noopEmbedder.GenerateEmbedding`
/// returning `&Embedding{Vector: []float32{}, Dimensions: 0, ...}`.
public struct NoopEmbedder: Embedder {
  public let dimensions: Int = 0

  public init() {}

  public func embed(_ text: String) async throws -> [Float] {
    []
  }
}
