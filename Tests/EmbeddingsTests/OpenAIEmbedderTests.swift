import Foundation
import Observability
import Testing

@testable import Embeddings

/// Builds an `OpenAIEmbedder` pointed at a unique stub host, returning the embedder, the host, and a
/// captured-request box. Callers register a handler on the host and tear it down with `defer`.
private func makeStubbedOpenAIEmbedder(
  apiKey: String = "sk-test", defaultModel: String = ""
) -> (embedder: OpenAIEmbedder, host: String, captured: EmbeddingsCapturedRequest) {
  let host = "\(UUID().uuidString.lowercased()).test"
  let embedder = OpenAIEmbedder(
    session: embeddingsStubbedSession(),
    observer: recordingObserver("test"),
    metrics: NoopMetricsProvider(),
    apiKey: apiKey,
    baseURL: "https://\(host)",
    defaultModel: defaultModel)
  return (embedder, host, EmbeddingsCapturedRequest())
}

private func okResponse(_ vector: [Double]) -> Data {
  let joined = vector.map { String($0) }.joined(separator: ",")
  return Data(#"{"data":[{"embedding":[\#(joined)]}]}"#.utf8)
}

@Suite("OpenAIEmbedder")
struct OpenAIEmbedderTests {
  @Test("a successful embed extracts the vector")
  func successExtractsVector() async throws {
    let (embedder, host, _) = makeStubbedOpenAIEmbedder()
    EmbeddingsStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: okResponse([0.1, 0.2, 0.3]), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    let vector = try await embedder.embed("hello world")

    #expect(vector == [0.1, 0.2, 0.3])
  }

  @Test("the request hits /embeddings with a bearer token and the resolved model")
  func requestShapeAndHeaders() async throws {
    let (embedder, host, captured) = makeStubbedOpenAIEmbedder(
      defaultModel: "text-embedding-3-large")
    EmbeddingsStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: okResponse([0.5]), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    _ = try await embedder.embed("hey")

    let request = try #require(captured.request)
    #expect(request.url?.path == "/embeddings")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

    let body = try #require(
      try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    #expect(body["model"] as? String == "text-embedding-3-large")
    #expect(body["input"] as? String == "hey")
    #expect(body["encoding_format"] as? String == "float")
  }

  @Test("an empty configured model falls back to the built-in default")
  func modelFallback() async throws {
    let (embedder, host, captured) = makeStubbedOpenAIEmbedder(defaultModel: "")
    EmbeddingsStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: okResponse([0.1]), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    _ = try await embedder.embed("x")

    let body = try #require(
      try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    #expect(body["model"] as? String == OpenAIEmbedder.defaultModel)
  }

  @Test("dimensions resolves from the known-model table, defaulting for an unknown model")
  func dimensionsResolution() {
    let small = OpenAIEmbedder(
      session: embeddingsStubbedSession(), observer: recordingObserver("t"),
      metrics: NoopMetricsProvider(), apiKey: "k", defaultModel: "text-embedding-3-small")
    #expect(small.dimensions == 1536)

    let large = OpenAIEmbedder(
      session: embeddingsStubbedSession(), observer: recordingObserver("t"),
      metrics: NoopMetricsProvider(), apiKey: "k", defaultModel: "text-embedding-3-large")
    #expect(large.dimensions == 3072)

    let unknown = OpenAIEmbedder(
      session: embeddingsStubbedSession(), observer: recordingObserver("t"),
      metrics: NoopMetricsProvider(), apiKey: "k", defaultModel: "some-future-model")
    #expect(unknown.dimensions == OpenAIEmbedder.knownModelDimensions[OpenAIEmbedder.defaultModel])
  }

  @Test("a 429 surfaces as rateLimit carrying Retry-After, and is not retried")
  func rateLimitCarriesRetryAfter() async throws {
    let (embedder, host, _) = makeStubbedOpenAIEmbedder()
    let calls = EmbeddingsCallCounter()
    EmbeddingsStubURLProtocol.register(host: host) { _ in
      calls.increment()
      return .respond(
        status: 429,
        body: Data(#"{"error":{"message":"slow down"}}"#.utf8),
        headers: ["Retry-After": "30"])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    await #expect(throws: EmbeddingsError.rateLimit(retryAfter: 30)) {
      try await embedder.embed("x")
    }
    #expect(calls.value == 1)  // no internal retry
  }

  @Test("a 401 surfaces as authentication")
  func authError() async throws {
    let (embedder, host, _) = makeStubbedOpenAIEmbedder()
    EmbeddingsStubURLProtocol.register(host: host) { _ in
      .respond(status: 401, body: Data(#"{"error":{"message":"bad key"}}"#.utf8), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    await #expect(throws: EmbeddingsError.authentication) {
      try await embedder.embed("x")
    }
  }

  @Test("a 2xx body that doesn't decode surfaces as malformedResponse")
  func malformedBody() async throws {
    let (embedder, host, _) = makeStubbedOpenAIEmbedder()
    EmbeddingsStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: Data("not json".utf8), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    await #expect {
      try await embedder.embed("x")
    } throws: { error in
      guard case EmbeddingsError.malformedResponse = error else { return false }
      return true
    }
  }

  @Test("a response with no data entries surfaces as malformedResponse")
  func emptyData() async throws {
    let (embedder, host, _) = makeStubbedOpenAIEmbedder()
    EmbeddingsStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: Data(#"{"data":[]}"#.utf8), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    await #expect {
      try await embedder.embed("x")
    } throws: { error in
      guard case EmbeddingsError.malformedResponse = error else { return false }
      return true
    }
  }

  @Test("the default batch embed loops the single-item call in order")
  func batchEmbedLoops() async throws {
    let (embedder, host, captured) = makeStubbedOpenAIEmbedder()
    let calls = EmbeddingsCallCounter()
    EmbeddingsStubURLProtocol.register(host: host) { request in
      calls.increment()
      captured.set(request)
      return .respond(status: 200, body: okResponse([0.1]), headers: [:])
    }
    defer { EmbeddingsStubURLProtocol.unregister(host) }

    let vectors = try await embedder.embed(["a", "b", "c"])

    #expect(vectors.count == 3)
    #expect(calls.value == 3)
  }
}
