import CircuitBreaking
import Foundation
import Observability
import Testing

@testable import Embeddings

@Suite("Embeddings config")
struct EmbeddingsConfigTests {
  private func pillars() -> Pillars {
    Pillars(logger: NoopLogger(), tracer: NoopTracer(), metrics: NoopMetricsProvider())
  }

  @Test("EmbeddingsConfig decodes Go's wire shape and resolves the provider")
  func decodesWireShape() throws {
    let json = Data(
      """
      {"provider":"openai","openai":{"apiKey":"sk-1","defaultModel":"text-embedding-3-large","timeout":5000000000}}
      """.utf8)
    let config = try JSONDecoder().decode(EmbeddingsConfig.self, from: json)
    #expect(config.provider == "openai")
    #expect(config.resolvedProvider == .openai)
    #expect(config.openai?.apiKey == "sk-1")
    #expect(config.openai?.defaultModel == "text-embedding-3-large")
    #expect(config.openai?.timeout == .seconds(5))
    #expect(config.onDevice == nil)
  }

  @Test("an empty JSON object decodes to Go's zero values")
  func emptyObjectDecodes() throws {
    let config = try JSONDecoder().decode(EmbeddingsConfig.self, from: Data("{}".utf8))
    #expect(config == EmbeddingsConfig())
    #expect(config.resolvedProvider == nil)
  }

  @Test("an empty OpenAIEmbedderConfig JSON object decodes to Go's zero values")
  func emptyOpenAIConfigDecodes() throws {
    let config = try JSONDecoder().decode(OpenAIEmbedderConfig.self, from: Data("{}".utf8))
    #expect(config == OpenAIEmbedderConfig())
    #expect(config.circuitBreaker == CircuitBreakerConfig())
  }

  @Test("provider resolution trims and lowercases, and rejects unknown values")
  func providerResolution() {
    #expect(EmbeddingsConfig(provider: "  OpenAI ").resolvedProvider == .openai)
    #expect(EmbeddingsConfig(provider: "onDevice").resolvedProvider == .onDevice)
    #expect(EmbeddingsConfig(provider: "").resolvedProvider == nil)
    #expect(EmbeddingsConfig(provider: "cohere").resolvedProvider == nil)
  }

  @Test("OpenAIEmbedderConfig omits empty strings and encodes timeout as integer nanoseconds")
  func providerConfigEncoding() throws {
    let config = OpenAIEmbedderConfig(apiKey: "sk-1", timeout: .milliseconds(1500))
    let object = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(config)) as? [String: Any])
    #expect(object["apiKey"] as? String == "sk-1")
    #expect(object["baseURL"] == nil)  // omitempty
    #expect(object["defaultModel"] == nil)  // omitempty
    #expect(object["timeout"] as? Int == 1_500_000_000)
    #expect(object["circuitBreaker"] != nil)
  }

  @Test("validate requires the selected provider's config and its API key")
  func validation() {
    // empty provider → noop, no config needed
    #expect(throws: Never.self) { try EmbeddingsConfig().validate() }
    // provider set but config missing
    #expect(throws: EmbeddingsError.invalidConfig("openai config required")) {
      try EmbeddingsConfig(provider: "openai").validate()
    }
    // provider + config but no key
    #expect(throws: EmbeddingsError.missingAPIKey) {
      try EmbeddingsConfig(openai: OpenAIEmbedderConfig(), provider: "openai").validate()
    }
    // valid
    #expect(throws: Never.self) {
      try EmbeddingsConfig(openai: OpenAIEmbedderConfig(apiKey: "sk-1"), provider: "openai")
        .validate()
    }
    // onDevice needs no config at all
    #expect(throws: Never.self) { try EmbeddingsConfig(provider: "onDevice").validate() }
    // unknown provider
    #expect(throws: EmbeddingsError.invalidConfig("unknown provider: cohere")) {
      try EmbeddingsConfig(provider: "cohere").validate()
    }
  }

  @Test("provideEmbedder selects the live embedder, defaulting to noop")
  func selector() throws {
    #expect(try EmbeddingsConfig().provideEmbedder(pillars: pillars()) is NoopEmbedder)
    #expect(
      try EmbeddingsConfig(openai: OpenAIEmbedderConfig(apiKey: "sk-1"), provider: "openai")
        .provideEmbedder(pillars: pillars()) is OpenAIEmbedder)
    #expect(throws: EmbeddingsError.invalidConfig("openai config required")) {
      try EmbeddingsConfig(provider: "openai").provideEmbedder(pillars: pillars())
    }
  }
}
