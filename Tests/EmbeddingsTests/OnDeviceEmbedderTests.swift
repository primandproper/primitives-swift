import NaturalLanguage
import Testing

@testable import Embeddings

/// `NLEmbedding.sentenceEmbedding(for:)` depends on a model being installed on the running OS/device,
/// which is not guaranteed on every CI runner. Every test below checks this up front and skips (rather
/// than fails) when unavailable, matching the "guarded by availability" requirement for the on-device
/// happy path.
private var englishModelAvailable: Bool {
  NLEmbedding.sentenceEmbedding(for: .english) != nil
}

@Suite("OnDeviceEmbedder")
struct OnDeviceEmbedderTests {
  @Test("embedding English text yields a vector matching the model's own dimension")
  func happyPath() async throws {
    try #require(englishModelAvailable)

    let embedder = try OnDeviceEmbedder(language: .english)
    #expect(embedder.dimensions > 0)

    let vector = try await embedder.embed("hello world")

    #expect(vector.count == embedder.dimensions)
  }

  @Test("an empty OnDeviceEmbedderConfig resolves to English")
  func configDefaultsToEnglish() async throws {
    try #require(englishModelAvailable)

    let embedder = try OnDeviceEmbedder(config: OnDeviceEmbedderConfig())
    let englishDirect = try OnDeviceEmbedder(language: .english)
    #expect(embedder.dimensions == englishDirect.dimensions)
  }

  @Test("semantically similar sentences embed closer than unrelated ones")
  func similarityIsMeaningful() async throws {
    try #require(englishModelAvailable)

    let embedder = try OnDeviceEmbedder(language: .english)
    let a = try await embedder.embed("The cat sat on the mat.")
    let b = try await embedder.embed("A cat was sitting on a mat.")
    let c = try await embedder.embed("Quarterly tax filings are due Monday.")

    #expect(cosineSimilarity(a, b) > cosineSimilarity(a, c))
  }

  @Test("no on-device model for a nonsense language code throws embeddingUnavailable")
  func unavailableLanguageThrows() {
    // "xx-not-a-real-language" is not a BCP-47 code NLLanguage recognizes as having an installed model.
    let language = NLLanguage("xx-not-a-real-language")
    #expect(throws: EmbeddingsError.embeddingUnavailable(language.rawValue)) {
      _ = try OnDeviceEmbedder(language: language)
    }
  }
}

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
  guard a.count == b.count, !a.isEmpty else { return 0 }
  var dot: Float = 0
  var normA: Float = 0
  var normB: Float = 0
  for i in 0..<a.count {
    dot += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  }
  guard normA > 0, normB > 0 else { return 0 }
  return dot / (normA.squareRoot() * normB.squareRoot())
}
