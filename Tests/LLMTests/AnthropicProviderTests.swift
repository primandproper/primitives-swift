import Foundation
import Observability
import Testing

@testable import LLM

private func makeStubbedAnthropic(
  apiKey: String = "sk-ant-test", defaultModel: String = ""
) -> (provider: AnthropicProvider, host: String, captured: CapturedRequest) {
  let host = "\(UUID().uuidString.lowercased()).test"
  let provider = AnthropicProvider(
    session: llmStubbedSession(),
    observer: recordingObserver("test"),
    metrics: NoopMetricsProvider(),
    apiKey: apiKey,
    baseURL: "https://\(host)",
    defaultModel: defaultModel)
  return (provider, host, CapturedRequest())
}

private func anthropicOK(_ text: String, stopReason: String = "end_turn") -> Data {
  Data(
    """
    {"content":[{"type":"text","text":"\(text)"}],"stop_reason":"\(stopReason)","usage":{"input_tokens":10,"output_tokens":5}}
    """.utf8)
}

@Suite("AnthropicProvider")
struct AnthropicProviderTests {
  @Test("a successful completion joins the text content blocks")
  func successJoinsTextBlocks() async throws {
    let (provider, host, _) = makeStubbedAnthropic()
    LLMStubURLProtocol.register(host: host) { _ in
      .respond(
        status: 200,
        body: Data(
          #"{"content":[{"type":"text","text":"one "},{"type":"text","text":"two"}],"stop_reason":"end_turn"}"#
            .utf8),
        headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    let result = try await provider.completion(
      CompletionParams(messages: [Message(role: .user, content: "hi")]))
    #expect(result.content == "one two")
  }

  @Test("the request hits /v1/messages with the x-api-key + anthropic-version headers and max_tokens")
  func requestShapeAndHeaders() async throws {
    let (provider, host, captured) = makeStubbedAnthropic()
    LLMStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: anthropicOK("ok"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    _ = try await provider.completion(
      CompletionParams(model: "claude-x", messages: [Message(role: .user, content: "hey")]))

    let request = try #require(captured.request)
    #expect(request.url?.path == "/v1/messages")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicProvider.apiVersion)

    let body = try #require(try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    #expect(body["model"] as? String == "claude-x")
    #expect(body["max_tokens"] as? Int == AnthropicProvider.defaultMaxTokens)
  }

  @Test("system turns are hoisted to the top-level system field and dropped from messages")
  func systemHoisting() async throws {
    let (provider, host, captured) = makeStubbedAnthropic()
    LLMStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: anthropicOK("ok"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    _ = try await provider.completion(
      CompletionParams(messages: [
        Message(role: .system, content: "you are terse"),
        Message(role: .system, content: "and kind"),
        Message(role: .user, content: "hi"),
        Message(role: .assistant, content: "hello"),
        Message(role: .tool, content: "tool output"),
      ]))

    let body = try #require(try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    // Two system turns joined with a blank line.
    #expect(body["system"] as? String == "you are terse\n\nand kind")
    let messages = try #require(body["messages"] as? [[String: Any]])
    // system turns removed; user/assistant kept; tool folded to a user turn.
    #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
    #expect(messages.last?["content"] as? String == "tool output")
  }

  @Test("no system turns means no system field on the wire")
  func noSystemFieldWhenAbsent() async throws {
    let (provider, host, captured) = makeStubbedAnthropic()
    LLMStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: anthropicOK("ok"), headers: [:])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    _ = try await provider.completion(
      CompletionParams(messages: [Message(role: .user, content: "hi")]))

    let body = try #require(try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    #expect(body["system"] == nil)
  }

  @Test("error classification is shared: a 429 surfaces as rateLimit")
  func rateLimit() async throws {
    let (provider, host, _) = makeStubbedAnthropic()
    LLMStubURLProtocol.register(host: host) { _ in
      .respond(
        status: 429,
        body: Data(#"{"type":"error","error":{"message":"overloaded"}}"#.utf8),
        headers: ["Retry-After": "12"])
    }
    defer { LLMStubURLProtocol.unregister(host) }

    await #expect(throws: LLMError.rateLimit(retryAfter: 12)) {
      try await provider.completion(CompletionParams(messages: [Message(role: .user, content: "x")]))
    }
  }
}
