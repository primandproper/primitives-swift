import Foundation

/// Errors surfaced by the ``Embedder`` conformers.
///
/// Go's `embeddings` package leans on plain `fmt`-wrapped errors per backend. This port instead gives
/// Search a typed, switchable failure. Every kept backend is on-device, so there is no HTTP status
/// classification here: a remote embedder needs a vendor API key on the handset and belongs behind a
/// `platform-go` service instead.
public enum EmbeddingsError: Error, Equatable, Sendable {
  /// The config failed validation. Carries the human-readable reason.
  case invalidConfig(String)
  /// No on-device embedding model is available for the requested language (``OnDeviceEmbedder``). Carries
  /// the BCP-47 language code that was requested.
  case embeddingUnavailable(String)
  /// The on-device model produced no vector for the given text (``OnDeviceEmbedder``) — e.g. empty input
  /// the tokenizer reduces to nothing. Carries the input that failed.
  case embeddingFailed(String)

  public var description: String {
    switch self {
    case .invalidConfig(let reason): return "invalid embeddings config: \(reason)"
    case .embeddingUnavailable(let language):
      return "no on-device embedding model available for language: \(language)"
    case .embeddingFailed(let text): return "on-device embedding failed for input: \(text)"
    }
  }
}

extension EmbeddingsError: LocalizedError {
  public var errorDescription: String? { description }
}
