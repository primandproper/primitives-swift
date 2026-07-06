import Foundation
import os

/// What a stubbed request should do when it reaches the fake transport. Mirrors `LLMTests`'
/// `LLMStubOutcome`.
enum EmbeddingsStubOutcome: Sendable {
  case respond(status: Int, body: Data, headers: [String: String])
  case fail(any Error & Sendable)
}

/// A hermetic `URLProtocol` stub so ``OpenAIEmbedder`` tests never hit the network. Handlers are keyed
/// by the request's **host**, so each test points its embedder at a unique `https://<uuid>.test` base
/// URL, keeping parallel `swift-testing` cases from clobbering each other — the identical approach
/// `LLMTests`' `LLMStubURLProtocol` takes.
final class EmbeddingsStubURLProtocol: URLProtocol, @unchecked Sendable {
  private static let registry =
    OSAllocatedUnfairLock<[String: @Sendable (URLRequest) -> EmbeddingsStubOutcome]>(
      initialState: [:])

  static func register(
    host: String, _ handler: @escaping @Sendable (URLRequest) -> EmbeddingsStubOutcome
  ) {
    registry.withLock { $0[host] = handler }
  }

  static func unregister(_ host: String) {
    registry.withLock { $0[host] = nil }
  }

  private static func handler(for host: String)
    -> (@Sendable (URLRequest) -> EmbeddingsStubOutcome)?
  {
    registry.withLock { $0[host] }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let host = request.url?.host, let handler = EmbeddingsStubURLProtocol.handler(for: host)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    switch handler(request) {
    case .respond(let status, let body, let headers):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .fail(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

/// A `URLSession` wired to the stub transport.
func embeddingsStubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [EmbeddingsStubURLProtocol.self]
  configuration.timeoutIntervalForRequest = 4
  configuration.timeoutIntervalForResource = 4
  return URLSession(configuration: configuration)
}

/// Reads a request's body, transparently draining `httpBodyStream` — `URLSession` converts an
/// `httpBody` into a stream by the time a `URLProtocol` sees the request, so `request.httpBody` is nil.
func embeddingsRequestBody(_ request: URLRequest) -> Data {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return Data() }
  stream.open()
  defer { stream.close() }
  var data = Data()
  let bufferSize = 4096
  var buffer = [UInt8](repeating: 0, count: bufferSize)
  while stream.hasBytesAvailable {
    let read = stream.read(&buffer, maxLength: bufferSize)
    if read <= 0 { break }
    data.append(buffer, count: read)
  }
  return data
}

/// A thread-safe call counter, used to prove an embedder makes exactly one request (no internal retry).
final class EmbeddingsCallCounter: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock(initialState: 0)
  @discardableResult func increment() -> Int {
    state.withLock {
      $0 += 1
      return $0
    }
  }
  var value: Int { state.withLock { $0 } }
}

/// A thread-safe one-shot box for a handler to hand the request it saw back to the test body.
final class EmbeddingsCapturedRequest: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
  func set(_ request: URLRequest) { state.withLock { $0 = request } }
  var request: URLRequest? { state.withLock { $0 } }
  var body: Data { request.map(embeddingsRequestBody) ?? Data() }
}
