import Foundation
import Observability
import Testing

@testable import LLM

/// Builds an `OpenAIProvider` pointed at a unique stub host, returning the provider, the host, and a
/// captured-request box. Callers register a handler on the host and tear it down with `defer`.
private func makeStubbedOpenAI(
  apiKey: String = "sk-test", defaultModel: String = ""
) -> (provider: OpenAIProvider, host: String, captured: CapturedRequest) {
  let host = "\(UUID().uuidString.lowercased()).test"
  let provider = OpenAIProvider(
    session: llmStubbedSession(),
    observer: recordingObserver("test"),
    metrics: NoopMetricsProvider(),
    apiKey: apiKey,
    baseURL: "https://\(host)",
    defaultModel: defaultModel)
  return (provider, host, CapturedRequest())
}

private func okResponse(content: String, finishReason: String = "stop", totalTokens: Int = 42)
  -> Data
{
  Data(
    """
    {"choices":[{"message":{"role":"assistant","content":"\(content)"},"finish_reason":"\(finishReason)"}],"usage":{"total_tokens":\(totalTokens)}}
    """.utf8)
}

@Suite("OpenAIProvider")
struct OpenAIProviderTests {
  @Test("a successful completion extracts the assistant text")
  func successExtractsContent() async throws {
    let (provider, host, _) = makeStubbedOpenAI()
    LLMStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: okResponse(content: "hi there"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    let result = try await provider.completion(
      CompletionParams(messages: [Message(role: .user, content: "hello")]))

    #expect(result.content == "hi there")
  }

  @Test("the request hits /chat/completions with a bearer token and maps roles straight through")
  func requestShapeAndHeaders() async throws {
    let (provider, host, captured) = makeStubbedOpenAI()
    LLMStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: okResponse(content: "ok"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    _ = try await provider.completion(
      CompletionParams(
        model: "gpt-4o",
        messages: [
          Message(role: .system, content: "be brief"),
          Message(role: .user, content: "hey"),
        ]))

    let request = try #require(captured.request)
    #expect(request.url?.path == "/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

    let body = try #require(
      try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    #expect(body["model"] as? String == "gpt-4o")
    // OpenAI accepts every role directly in the messages array — no reshaping.
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] as? String == "system")
    #expect(messages[1]["role"] as? String == "user")
    #expect(messages[1]["content"] as? String == "hey")
  }

  @Test("an empty request model falls back to the configured default, then the built-in default")
  func modelFallback() async throws {
    // configured default wins when params.model is empty
    let (configured, host1, captured1) = makeStubbedOpenAI(defaultModel: "gpt-4.1-mini")
    LLMStubURLProtocol.register(host: host1) { request in
      captured1.set(request)
      return .respond(status: 200, body: okResponse(content: "ok"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host1) }
    _ = try await configured.completion(
      CompletionParams(messages: [Message(role: .user, content: "x")]))
    let body1 = try #require(
      try JSONSerialization.jsonObject(with: captured1.body) as? [String: Any])
    #expect(body1["model"] as? String == "gpt-4.1-mini")

    // built-in default when neither is set
    let (bare, host2, captured2) = makeStubbedOpenAI(defaultModel: "")
    LLMStubURLProtocol.register(host: host2) { request in
      captured2.set(request)
      return .respond(status: 200, body: okResponse(content: "ok"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host2) }
    _ = try await bare.completion(CompletionParams(messages: [Message(role: .user, content: "x")]))
    let body2 = try #require(
      try JSONSerialization.jsonObject(with: captured2.body) as? [String: Any])
    #expect(body2["model"] as? String == OpenAIProvider.defaultModel)
  }

  @Test("a 429 surfaces as rateLimit carrying Retry-After, and is not retried")
  func rateLimitCarriesRetryAfter() async throws {
    let (provider, host, _) = makeStubbedOpenAI()
    let calls = OSCounter()
    LLMStubURLProtocol.register(host: host) { _ in
      calls.increment()
      return .respond(
        status: 429,
        body: Data(#"{"error":{"message":"slow down"}}"#.utf8),
        headers: ["Retry-After": "30"])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    await #expect(throws: LLMError.rateLimit(retryAfter: 30)) {
      try await provider.completion(
        CompletionParams(messages: [Message(role: .user, content: "x")]))
    }
    #expect(calls.value == 1)  // no internal retry
  }

  @Test("a 401 surfaces as authentication")
  func authError() async throws {
    let (provider, host, _) = makeStubbedOpenAI()
    LLMStubURLProtocol.register(host: host) { _ in
      .respond(status: 401, body: Data(#"{"error":{"message":"bad key"}}"#.utf8), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    await #expect(throws: LLMError.authentication) {
      try await provider.completion(
        CompletionParams(messages: [Message(role: .user, content: "x")]))
    }
  }

  @Test("a 2xx body that doesn't decode surfaces as malformedResponse")
  func malformedBody() async throws {
    let (provider, host, _) = makeStubbedOpenAI()
    LLMStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: Data("not json".utf8), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    await #expect {
      try await provider.completion(
        CompletionParams(messages: [Message(role: .user, content: "x")]))
    } throws: { error in
      guard case LLMError.malformedResponse = error else { return false }
      return true
    }
  }

  @Test("a completion with no choices yields empty content, matching Go")
  func emptyChoices() async throws {
    let (provider, host, _) = makeStubbedOpenAI()
    LLMStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: Data(#"{"choices":[]}"#.utf8), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    let result = try await provider.completion(
      CompletionParams(messages: [Message(role: .user, content: "x")]))
    #expect(result.content == "")
  }
}
