import Foundation
import os

/// What a stubbed request should do when it reaches the fake transport.
enum AnalyticsStubOutcome: Sendable {
  case respond(status: Int, body: Data = Data(), headers: [String: String] = [:])
  case fail(any Error & Sendable)
}

/// A hermetic `URLProtocol` stub so the analytics reporters never hit the network.
///
/// The reporters build their own `URLRequest`s (fixed path/headers), so handlers are keyed by the
/// request's **host**. Each test points its reporter at a unique `https://<uuid>.test` endpoint and
/// registers a handler under that host, keeping parallel `swift-testing` cases from clobbering each
/// other. The handler both captures the request it saw and decides the response.
final class AnalyticsStubURLProtocol: URLProtocol, @unchecked Sendable {
  private static let registry =
    OSAllocatedUnfairLock<[String: @Sendable (URLRequest) -> AnalyticsStubOutcome]>(initialState: [:])

  static func register(
    host: String, _ handler: @escaping @Sendable (URLRequest) -> AnalyticsStubOutcome
  ) {
    registry.withLock { $0[host] = handler }
  }

  static func unregister(_ host: String) {
    registry.withLock { $0[host] = nil }
  }

  private static func handler(for host: String) -> (@Sendable (URLRequest) -> AnalyticsStubOutcome)? {
    registry.withLock { $0[host] }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let host = request.url?.host, let handler = AnalyticsStubURLProtocol.handler(for: host) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    switch handler(request) {
    case let .respond(status, body, headers):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case let .fail(error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

/// A `URLSession` wired to the stub transport.
func analyticsStubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [AnalyticsStubURLProtocol.self]
  configuration.timeoutIntervalForRequest = 4
  configuration.timeoutIntervalForResource = 4
  return URLSession(configuration: configuration)
}

/// Reads a request's body, transparently draining `httpBodyStream` — `URLSession` converts an
/// `httpBody` into a stream by the time a `URLProtocol` sees the request, so `request.httpBody` is nil.
func analyticsRequestBody(_ request: URLRequest) -> Data {
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

/// A thread-safe call counter, used to prove a reporter buffers (zero requests) until flushed.
final class AnalyticsCallCounter: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock(initialState: 0)
  @discardableResult func increment() -> Int { state.withLock { $0 += 1; return $0 } }
  var value: Int { state.withLock { $0 } }
}

/// A thread-safe one-shot box for a handler to hand the request it saw back to the test body.
final class AnalyticsCapturedRequest: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
  func set(_ request: URLRequest) { state.withLock { $0 = request } }
  var request: URLRequest? { state.withLock { $0 } }
  var body: Data { request.map(analyticsRequestBody) ?? Data() }

  /// The captured request body decoded as a JSON object.
  func json() -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
  }
}
