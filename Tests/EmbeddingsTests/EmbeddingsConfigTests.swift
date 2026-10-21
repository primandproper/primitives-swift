import Foundation
import Observability
import Testing

@testable import Embeddings

@Suite("Embeddings config")
struct EmbeddingsConfigTests {
  private func pillars() -> Pillars {
    Pillars(logger: NoopLogger(), tracer: NoopTracer(), metrics: NoopMetricsProvider())
  }

  @Test("EmbeddingsConfig decodes its wire shape and resolves the provider")
  func decodesWireShape() throws {
    let json = Data(
      """
      {"provider":"ondevice","onDevice":{"language":"fr"}}
      """.utf8)
    let config = try JSONDecoder().decode(EmbeddingsConfig.self, from: json)
    #expect(config.provider == "ondevice")
    #expect(config.resolvedProvider == .onDevice)
    #expect(config.onDevice?.language == "fr")
  }

  @Test("a Go-authored payload's remote-backend keys decode and are ignored")
  func ignoresDroppedBackends() throws {
    let json = Data(
      """
      {"provider":"openai","openai":{"apiKey":"sk-1"},"cohere":{},"ollama":{}}
      """.utf8)
    let config = try JSONDecoder().decode(EmbeddingsConfig.self, from: json)
    #expect(config == EmbeddingsConfig(provider: "openai"))
    #expect(config.resolvedProvider == nil)
  }

  @Test("an empty JSON object decodes to Go's zero values")
  func emptyObjectDecodes() throws {
    let config = try JSONDecoder().decode(EmbeddingsConfig.self, from: Data("{}".utf8))
    #expect(config == EmbeddingsConfig())
    #expect(config.resolvedProvider == nil)
  }

  @Test("provider resolution trims and lowercases, and rejects unknown values")
  func providerResolution() {
    #expect(EmbeddingsConfig(provider: "  OnDevice ").resolvedProvider == .onDevice)
    #expect(EmbeddingsConfig(provider: "").resolvedProvider == nil)
    #expect(EmbeddingsConfig(provider: "openai").resolvedProvider == nil)
    #expect(EmbeddingsConfig(provider: "cohere").resolvedProvider == nil)
  }

  @Test("validate accepts noop and onDevice, and rejects unknown providers")
  func validation() {
    // empty provider → noop, no config needed
    #expect(throws: Never.self) { try EmbeddingsConfig().validate() }
    // onDevice needs no config at all
    #expect(throws: Never.self) { try EmbeddingsConfig(provider: "onDevice").validate() }
    // a dropped remote backend is now unknown
    #expect(throws: EmbeddingsError.invalidConfig("unknown provider: openai")) {
      try EmbeddingsConfig(provider: "openai").validate()
    }
    #expect(throws: EmbeddingsError.invalidConfig("unknown provider: cohere")) {
      try EmbeddingsConfig(provider: "cohere").validate()
    }
  }

  @Test("provideEmbedder defaults to noop, including for a dropped remote backend")
  func selector() throws {
    #expect(try EmbeddingsConfig().provideEmbedder(pillars: pillars()) is NoopEmbedder)
    #expect(
      try EmbeddingsConfig(provider: "openai").provideEmbedder(pillars: pillars()) is NoopEmbedder)
  }
}
