import NaturalLanguage

/// A **native, offline** ``Embedder`` with no Go counterpart, backed by `NaturalLanguage`'s
/// `NLEmbedding.sentenceEmbedding(for:)`. Free (no API key), private (nothing leaves the device), and
/// synchronous under the hood — the natural default embedder for a mobile app, where Go's server-side
/// deployment has no equivalent option at all.
///
/// **Why `NLEmbedding` and not `NLContextualEmbedding`.** `NaturalLanguage` also ships
/// `NLContextualEmbedding`, a transformer-based contextual embedder that would generally produce
/// higher-quality vectors. It is not adopted here for two reasons: (1) it requires asynchronously
/// downloading model assets (`requiresAssets` / `load()`) before first use, an activation flow this thin
/// seam does not want to own, and (2) its availability floor (iOS 17/macOS 14) is higher than this
/// package's iOS 16/macOS 13 target. `NLEmbedding.sentenceEmbedding(for:)`, by contrast, is synchronous,
/// ships its static embedding tables with the OS (no download), and has been available since iOS
/// 15/macOS 12 — comfortably under this package's floor. ``Embedder`` is intentionally shaped as a plain
/// `async` seam (mirroring `Sources/LLM`'s note about a future Foundation Models adapter), so a
/// `NLContextualEmbedding`-backed conformer can be added later behind an availability check without
/// reshaping this protocol.
///
/// **Availability is a construction-time concern, not a per-call one.** `NLEmbedding.sentenceEmbedding(for:)`
/// returns `nil` when no model is installed for the requested language, so ``init(language:)`` throws
/// ``EmbeddingsError/embeddingUnavailable(_:)`` up front — a caller learns immediately whether the
/// on-device path is usable for its target language, rather than discovering it lazily on the first
/// ``embed(_:)`` call.
public struct OnDeviceEmbedder: Embedder {
  public let dimensions: Int

  private let box: NLEmbeddingBox

  /// Loads the on-device sentence embedding model for `language` (default `.english`). Throws
  /// ``EmbeddingsError/embeddingUnavailable(_:)`` if no such model is installed on the running OS/device.
  public init(language: NLLanguage = .english) throws {
    guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
      throw EmbeddingsError.embeddingUnavailable(language.rawValue)
    }
    self.box = NLEmbeddingBox(embedding)
    self.dimensions = embedding.dimension
  }

  /// Convenience initializer from ``OnDeviceEmbedderConfig``. An empty ``OnDeviceEmbedderConfig/language``
  /// resolves to `.english`.
  public init(config: OnDeviceEmbedderConfig) throws {
    let language =
      config.language.isEmpty ? NLLanguage.english : NLLanguage(rawValue: config.language)
    try self.init(language: language)
  }

  public func embed(_ text: String) async throws -> [Float] {
    guard let vector = box.embedding.vector(for: text) else {
      throw EmbeddingsError.embeddingFailed(text)
    }
    return vector.map(Float.init)
  }
}

/// `NLEmbedding` is a reference type not marked `Sendable` by the framework, though Apple documents its
/// instances as immutable and safe for concurrent read access once constructed (there is no mutating API
/// on it at all). This box lets ``OnDeviceEmbedder`` — a `Sendable` `struct` — hold one, the same
/// `@unchecked Sendable`-wrapping move this repo uses elsewhere for immutable system-framework handles
/// (e.g. `Authentication`'s `JWTVerificationKey`).
private final class NLEmbeddingBox: @unchecked Sendable {
  let embedding: NLEmbedding
  init(_ embedding: NLEmbedding) { self.embedding = embedding }
}
