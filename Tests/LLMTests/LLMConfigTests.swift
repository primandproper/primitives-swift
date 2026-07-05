import Foundation
import Observability
import Testing

@testable import LLM

@Suite("LLM config")
struct LLMConfigTests {
  private func pillars() -> Pillars {
    Pillars(logger: NoopLogger(), tracer: NoopTracer(), metrics: NoopMetricsProvider())
  }

  @Test("LLMConfig decodes Go's wire shape and resolves the provider")
  func decodesWireShape() throws {
    let json = Data(
      """
      {"provider":"openai","openai":{"apiKey":"sk-1","defaultModel":"gpt-4o","timeout":5000000000}}
      """.utf8)
    let config = try JSONDecoder().decode(LLMConfig.self, from: json)
    #expect(config.provider == "openai")
    #expect(config.resolvedProvider == .openai)
    #expect(config.openai?.apiKey == "sk-1")
    #expect(config.openai?.defaultModel == "gpt-4o")
    #expect(config.openai?.timeout == .seconds(5))
    #expect(config.anthropic == nil)
  }

  @Test("provider resolution trims and lowercases, and rejects unknown values")
  func providerResolution() {
    #expect(LLMConfig(provider: "  Anthropic ").resolvedProvider == .anthropic)
    #expect(LLMConfig(provider: "").resolvedProvider == nil)
    #expect(LLMConfig(provider: "gemini").resolvedProvider == nil)
  }

  @Test("LLMProviderConfig omits empty strings and encodes timeout as integer nanoseconds")
  func providerConfigEncoding() throws {
    let config = LLMProviderConfig(apiKey: "sk-1", timeout: .milliseconds(1500))
    let object = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(config)) as? [String: Any])
    #expect(object["apiKey"] as? String == "sk-1")
    #expect(object["baseURL"] == nil)  // omitempty
    #expect(object["defaultModel"] == nil)  // omitempty
    #expect(object["timeout"] as? Int == 1_500_000_000)
  }

  @Test("validate requires the selected provider's config and its API key")
  func validation() {
    // empty provider → noop, no config needed
    #expect(throws: Never.self) { try LLMConfig().validate() }
    // provider set but config missing
    #expect(throws: LLMError.invalidConfig("openai config required")) {
      try LLMConfig(provider: "openai").validate()
    }
    // provider + config but no key
    #expect(throws: LLMError.missingAPIKey) {
      try LLMConfig(openai: LLMProviderConfig(), provider: "openai").validate()
    }
    // valid
    #expect(throws: Never.self) {
      try LLMConfig(openai: LLMProviderConfig(apiKey: "sk-1"), provider: "openai").validate()
    }
  }

  @Test("provideLLMProvider selects the live provider, defaulting to noop")
  func selector() throws {
    #expect(
      try LLMConfig().provideLLMProvider(pillars: pillars()) is NoopLLMProvider)
    #expect(
      try LLMConfig(openai: LLMProviderConfig(apiKey: "sk-1"), provider: "openai")
        .provideLLMProvider(pillars: pillars()) is OpenAIProvider)
    #expect(
      try LLMConfig(anthropic: LLMProviderConfig(apiKey: "sk-1"), provider: "anthropic")
        .provideLLMProvider(pillars: pillars()) is AnthropicProvider)
    #expect(throws: LLMError.invalidConfig("anthropic config required")) {
      try LLMConfig(provider: "anthropic").provideLLMProvider(pillars: pillars())
    }
  }
}

@Suite("Noop and mock providers")
struct NoopAndMockTests {
  @Test("the noop provider returns empty content")
  func noopIsEmpty() async throws {
    let result = try await NoopLLMProvider().completion(
      CompletionParams(messages: [Message(role: .user, content: "x")]))
    #expect(result.content == "")
  }

  @Test("the mock records calls and runs its handler")
  func mockRecordsAndHandles() async throws {
    let mock = LLMProviderMock { params in
      CompletionResult(content: "echo: \(params.messages.first?.content ?? "")")
    }
    let result = try await mock.completion(
      CompletionParams(model: "m", messages: [Message(role: .user, content: "hi")]))
    #expect(result.content == "echo: hi")

    let calls = await mock.completionCalls
    #expect(calls.count == 1)
    #expect(calls.first?.model == "m")
  }

  @Test("an unset mock handler returns empty content")
  func mockDefaultsEmpty() async throws {
    let mock = LLMProviderMock()
    let result = try await mock.completion(CompletionParams(messages: []))
    #expect(result.content == "")
  }
}
