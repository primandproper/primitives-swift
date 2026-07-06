import CircuitBreaking
import Foundation
import Testing
import os

@testable import FeatureFlags

// MARK: - Hermetic transport stub

/// What a stubbed decide request should do when it reaches the fake transport.
enum PHStubOutcome: Sendable {
  case respond(status: Int, body: Data)
  case fail(any Error & Sendable)
}

/// A `URLProtocol` stub keyed by request host, so ``PostHogFeatureFlagManager`` never hits the network.
/// Each test points its manager at a unique `https://<uuid>.test` endpoint and registers a handler under
/// that host, keeping parallel `swift-testing` cases from clobbering each other. Modeled on the LLM
/// module's `LLMStubURLProtocol`.
final class PHStubURLProtocol: URLProtocol, @unchecked Sendable {
  private static let registry =
    OSAllocatedUnfairLock<[String: @Sendable (URLRequest) -> PHStubOutcome]>(initialState: [:])

  static func register(host: String, _ handler: @escaping @Sendable (URLRequest) -> PHStubOutcome) {
    registry.withLock { $0[host] = handler }
  }

  static func unregister(_ host: String) {
    registry.withLock { $0[host] = nil }
  }

  private static func handler(for host: String) -> (@Sendable (URLRequest) -> PHStubOutcome)? {
    registry.withLock { $0[host] }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let host = request.url?.host, let handler = PHStubURLProtocol.handler(for: host) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    switch handler(request) {
    case .respond(let status, let body):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .fail(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private func phStubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [PHStubURLProtocol.self]
  configuration.timeoutIntervalForRequest = 4
  configuration.timeoutIntervalForResource = 4
  return URLSession(configuration: configuration)
}

/// Reads a request's body, transparently draining `httpBodyStream` (URLSession converts `httpBody` into a
/// stream before a `URLProtocol` sees it).
private func phRequestBody(_ request: URLRequest) -> Data {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return Data() }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while stream.hasBytesAvailable {
    let read = stream.read(&buffer, maxLength: buffer.count)
    if read <= 0 { break }
    data.append(buffer, count: read)
  }
  return data
}

/// A one-shot thread-safe box handing the captured request back to the test body.
private final class CapturedRequest: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
  func set(_ request: URLRequest) { state.withLock { $0 = request } }
  var request: URLRequest? { state.withLock { $0 } }
  var body: Data { request.map(phRequestBody) ?? Data() }
}

/// An always-open circuit breaker, standing in for the missing `CircuitBreaking` mock so a test can prove
/// fail-open when the breaker rejects the call.
private struct OpenCircuitBreaker: CircuitBreaker {
  func recordFailure() {}
  func recordSuccess() {}
  func canProceed() -> Bool { false }
}

// MARK: - Fixtures

/// The exact `featureFlags` shape the Go `posthog` package's test server returns
/// (`featureflags/posthog/feature_flag_manager_test.go`): booleans are booleans, but multivariate
/// int/float/object variants arrive as JSON *strings*.
private let goParityFlags = Data(
  #"""
  {
    "featureFlags": {
      "bool-flag": true,
      "off-flag": false,
      "string-flag": "hello-world",
      "int-flag": "42",
      "float-flag": "3.14",
      "object-flag": "{\"key\":\"value\"}"
    },
    "featureFlagPayloads": {}
  }
  """#.utf8)

private func makeManager(
  host: String,
  circuitBreaker: any CircuitBreaker = NoopCircuitBreaker()
) -> PostHogFeatureFlagManager {
  PostHogFeatureFlagManager(
    projectAPIKey: "phc_test_key",
    endpoint: "https://\(host)",
    session: phStubbedSession(),
    circuitBreaker: circuitBreaker)
}

private func evalContext() -> EvaluationContext {
  EvaluationContext(targetingKey: "user-123", attributes: ["plan": "pro"])
}

// MARK: - Tests

@Suite("PostHogFeatureFlagManager")
struct PostHogFeatureFlagManagerTests {
  @Test("issues the decide request PostHog expects")
  func requestShape() async throws {
    let host = "\(UUID().uuidString).test"
    let captured = CapturedRequest()
    PHStubURLProtocol.register(host: host) { request in
      captured.set(request)
      return .respond(status: 200, body: goParityFlags)
    }
    defer { PHStubURLProtocol.unregister(host) }

    _ = try await makeManager(host: host).canUseFeature("bool-flag", context: evalContext())

    let request = try #require(captured.request)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString.hasSuffix("/flags/?v=2") == true)
    #expect(request.url?.query == "v=2")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let json = try #require(
      try JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
    #expect(json["api_key"] as? String == "phc_test_key")
    #expect(json["distinct_id"] as? String == "user-123")
    let personProps = try #require(json["person_properties"] as? [String: Any])
    #expect(personProps["plan"] as? String == "pro")
  }

  @Test("parses each of the five typed evaluators from the Go-parity response")
  func parsesAllEvaluators() async throws {
    let host = "\(UUID().uuidString).test"
    PHStubURLProtocol.register(host: host) { _ in .respond(status: 200, body: goParityFlags) }
    defer { PHStubURLProtocol.unregister(host) }
    let manager = makeManager(host: host)
    let ctx = evalContext()

    #expect(try await manager.canUseFeature("bool-flag", context: ctx) == true)
    #expect(try await manager.canUseFeature("off-flag", context: ctx) == false)
    // A present multivariate variant reads as "enabled" for the boolean evaluator.
    #expect(try await manager.canUseFeature("string-flag", context: ctx) == true)

    #expect(
      try await manager.stringValue(for: "string-flag", default: "fallback", context: ctx)
        == "hello-world")
    #expect(try await manager.int64Value(for: "int-flag", default: 0, context: ctx) == 42)
    #expect(
      try await manager.float64Value(for: "float-flag", default: 0, context: ctx) == 3.14)

    let object = try await manager.objectValue(
      for: "object-flag", default: ["default": true], context: ctx)
    #expect(object == ["key": "value"])
  }

  @Test("reads an object payload from featureFlagPayloads when present")
  func parsesPayloadObject() async throws {
    let host = "\(UUID().uuidString).test"
    let body = Data(
      #"""
      {
        "featureFlags": {"cfg-flag": "control"},
        "featureFlagPayloads": {"cfg-flag": "{\"limit\":10}"}
      }
      """#.utf8)
    PHStubURLProtocol.register(host: host) { _ in .respond(status: 200, body: body) }
    defer { PHStubURLProtocol.unregister(host) }

    let result = try await makeManager(host: host).objectValue(
      for: "cfg-flag", default: .null, context: evalContext())
    #expect(result == ["limit": 10])
  }

  @Test("fails open to the caller's default on a non-2xx status")
  func failsOpenOnHTTPError() async throws {
    let host = "\(UUID().uuidString).test"
    PHStubURLProtocol.register(host: host) { _ in .respond(status: 403, body: Data()) }
    defer { PHStubURLProtocol.unregister(host) }
    let manager = makeManager(host: host)
    let ctx = evalContext()

    #expect(try await manager.canUseFeature("bool-flag", context: ctx) == false)
    #expect(
      try await manager.stringValue(for: "string-flag", default: "fallback", context: ctx)
        == "fallback")
    #expect(try await manager.int64Value(for: "int-flag", default: 7, context: ctx) == 7)
    #expect(try await manager.float64Value(for: "float-flag", default: 1.5, context: ctx) == 1.5)
    let object = try await manager.objectValue(
      for: "object-flag", default: ["k": "v"], context: ctx)
    #expect(object == ["k": "v"])
  }

  @Test("fails open to the caller's default on a malformed body")
  func failsOpenOnMalformedBody() async throws {
    let host = "\(UUID().uuidString).test"
    PHStubURLProtocol.register(host: host) { _ in
      .respond(status: 200, body: Data("this is not json".utf8))
    }
    defer { PHStubURLProtocol.unregister(host) }
    let manager = makeManager(host: host)
    let ctx = evalContext()

    #expect(try await manager.canUseFeature("bool-flag", context: ctx) == false)
    #expect(
      try await manager.stringValue(for: "string-flag", default: "fallback", context: ctx)
        == "fallback")
    #expect(try await manager.objectValue(for: "object-flag", default: 99, context: ctx) == 99)
  }

  @Test("fails open to the caller's default on a transport error")
  func failsOpenOnTransportError() async throws {
    let host = "\(UUID().uuidString).test"
    PHStubURLProtocol.register(host: host) { _ in .fail(URLError(.notConnectedToInternet)) }
    defer { PHStubURLProtocol.unregister(host) }

    #expect(
      try await makeManager(host: host).int64Value(
        for: "int-flag", default: 5, context: evalContext())
        == 5)
  }

  @Test("fails open when the circuit breaker is open, without issuing a request")
  func failsOpenWhenCircuitOpen() async throws {
    let host = "\(UUID().uuidString).test"
    let hit = OSAllocatedUnfairLock(initialState: false)
    PHStubURLProtocol.register(host: host) { _ in
      hit.withLock { $0 = true }
      return .respond(status: 200, body: goParityFlags)
    }
    defer { PHStubURLProtocol.unregister(host) }

    let manager = makeManager(host: host, circuitBreaker: OpenCircuitBreaker())
    let result = try await manager.canUseFeature("bool-flag", context: evalContext())
    #expect(result == false)
    #expect(hit.withLock { $0 } == false)
  }

  @Test("an unknown flag returns the caller's default")
  func unknownFlagReturnsDefault() async throws {
    let host = "\(UUID().uuidString).test"
    PHStubURLProtocol.register(host: host) { _ in .respond(status: 200, body: goParityFlags) }
    defer { PHStubURLProtocol.unregister(host) }

    #expect(
      try await makeManager(host: host).stringValue(
        for: "missing-flag", default: "fallback", context: evalContext()) == "fallback")
  }

  @Test("empty endpoint resolves to PostHog US Cloud")
  func defaultEndpoint() {
    #expect(PostHogFeatureFlagManager.defaultEndpoint == "https://us.i.posthog.com")
  }
}
