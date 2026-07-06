import Foundation
import Testing

@testable import LLM

@Suite("LLM doubles")
struct LLMDoublesTests {
  @Test("NoopLLMProvider always yields empty content")
  func noopEmpty() async throws {
    let provider: any LLMProvider = NoopLLMProvider()
    let result = try await provider.completion(
      CompletionParams(model: "x", messages: [Message(role: .user, content: "hi")]))
    #expect(result.content == "")
  }

  @Test("LLMProviderMock with no handler returns empty content and records the call")
  func mockUnsetRecords() async throws {
    let mock = LLMProviderMock()
    let params = CompletionParams(model: "m", messages: [Message(role: .user, content: "hi")])

    let result = try await mock.completion(params)

    #expect(result.content == "")
    let calls = await mock.completionCalls
    #expect(calls == [params])
  }

  @Test("setCompletionHandler scripts the return post-init (can't assign the var cross-actor)")
  func mockSetHandler() async throws {
    let mock = LLMProviderMock()
    await mock.setCompletionHandler { params in CompletionResult(content: "echo:\(params.model)") }

    let result = try await mock.completion(CompletionParams(model: "gpt-x", messages: []))

    #expect(result.content == "echo:gpt-x")
  }

  @Test("a throwing handler propagates its typed LLMError")
  func mockThrows() async throws {
    let mock = LLMProviderMock(completionHandler: { _ in throw LLMError.authentication })
    await #expect(throws: LLMError.authentication) {
      _ = try await mock.completion(CompletionParams(messages: []))
    }
  }
}

/// Runs `sendLLMRequest` against a hermetic stub returning `outcome`, so the transport's status→error
/// classification can be asserted without a network.
private func transport(_ outcome: LLMStubOutcome, model: String) async throws -> Data {
  let host = "\(UUID().uuidString).test"
  LLMStubURLProtocol.register(host: host) { _ in outcome }
  defer { LLMStubURLProtocol.unregister(host) }
  let request = URLRequest(url: URL(string: "https://\(host)/v1/messages")!)
  return try await sendLLMRequest(request, session: llmStubbedSession(), model: model)
}

private func jsonError(_ message: String) -> Data {
  Data(#"{"error":{"message":"\#(message)"}}"#.utf8)
}

@Suite("LLM transport error classification")
struct LLMTransportClassificationTests {
  @Test("404 maps to modelNotFound carrying the request's model")
  func notFound() async {
    await #expect(throws: LLMError.modelNotFound("gpt-x")) {
      _ = try await transport(
        .respond(status: 404, body: jsonError("no such model"), headers: [:]), model: "gpt-x")
    }
  }

  @Test("a 400 attributing failure to the model routes to modelNotFound")
  func badRequestModel() async {
    await #expect(throws: LLMError.modelNotFound("foo")) {
      _ = try await transport(
        .respond(status: 400, body: jsonError("The model `foo` does not exist"), headers: [:]),
        model: "foo")
    }
  }

  @Test("an unrelated 400 routes to invalidRequest carrying the provider message")
  func badRequestOther() async {
    await #expect(throws: LLMError.invalidRequest("bad params")) {
      _ = try await transport(
        .respond(status: 400, body: jsonError("bad params"), headers: [:]), model: "m")
    }
  }

  @Test("a non-JSON error body falls back to the raw body as the provider message")
  func nonJSONBody() async {
    await #expect(throws: LLMError.provider(status: 502, message: "Bad Gateway")) {
      _ = try await transport(
        .respond(status: 502, body: Data("Bad Gateway".utf8), headers: [:]), model: "m")
    }
  }

  @Test("an empty error body yields a placeholder message, not a crash")
  func emptyBody() async {
    await #expect(throws: LLMError.provider(status: 500, message: "no response body")) {
      _ = try await transport(.respond(status: 500, body: Data(), headers: [:]), model: "m")
    }
  }

  @Test("429 with Retry-After surfaces rateLimit and is not swallowed")
  func rateLimit() async {
    await #expect(throws: LLMError.rateLimit(retryAfter: 7)) {
      _ = try await transport(
        .respond(status: 429, body: Data(), headers: ["Retry-After": "7"]), model: "m")
    }
  }

  @Test("a transport-level URLError propagates raw (no typed LLMError swallows it)")
  func urlErrorPropagates() async {
    await #expect(throws: URLError.self) {
      _ = try await transport(.fail(URLError(.notConnectedToInternet)), model: "m")
    }
  }

  @Test("a 2xx response returns its body untouched")
  func success() async throws {
    let body = try await transport(
      .respond(status: 200, body: Data(#"{"ok":true}"#.utf8), headers: [:]), model: "m")
    #expect(String(data: body, encoding: .utf8) == #"{"ok":true}"#)
  }
}
