import Foundation
import os

/// What a stubbed request should do when it reaches the fake transport.
enum StubOutcome: Sendable {
  case respond(status: Int, body: Data, headers: [String: String])
  case fail(any Error & Sendable)
  /// Spin until the `URLSession` task is cancelled (i.e. `stopLoading` fires), then fail with
  /// `URLError.cancelled` — used to prove cancellation propagates without touching the network.
  case blockUntilCancelled
}

/// A hermetic `URLProtocol` stub so tests never hit the network.
///
/// Handlers are keyed by a per-request token carried in the `X-Stub-Token` header, not by a single
/// global handler, so parallel `swift-testing` cases can't clobber each other's stubs. Each test
/// registers a handler under a unique token, sets that header on its requests, and unregisters on the
/// way out.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  static let tokenHeader = "X-Stub-Token"

  private static let registry =
    OSAllocatedUnfairLock<[String: @Sendable (URLRequest) -> StubOutcome]>(initialState: [:])

  static func register(_ token: String, _ handler: @escaping @Sendable (URLRequest) -> StubOutcome)
  {
    registry.withLock { $0[token] = handler }
  }

  static func unregister(_ token: String) {
    registry.withLock { $0[token] = nil }
  }

  private static func handler(for token: String) -> (@Sendable (URLRequest) -> StubOutcome)? {
    registry.withLock { $0[token] }
  }

  /// Set only for the ``StubOutcome/blockUntilCancelled`` case, so `stopLoading` knows to report the
  /// cancellation rather than treating teardown of an already-completed request as a no-op.
  private let parkedForCancellation = OSAllocatedUnfairLock(initialState: false)

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard
      let token = request.value(forHTTPHeaderField: StubURLProtocol.tokenHeader),
      let handler = StubURLProtocol.handler(for: token)
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
    case .blockUntilCancelled:
      // Do NOT block the loader thread — a busy-wait here starves CFNetwork's URLProtocol worker
      // pool and makes sibling stubbed requests time out under parallel test execution. Leave the
      // request pending instead; when the task is cancelled the loading system calls `stopLoading`,
      // which reports the cancellation.
      parkedForCancellation.withLock { $0 = true }
    }
  }

  override func stopLoading() {
    // Only the parked cancellation case needs to synthesize an error; for a request that already
    // finished (responded/failed), teardown is a no-op.
    if parkedForCancellation.withLock({ $0 }) {
      client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
  }
}

/// A `URLSession` wired to the stub transport. `.ephemeral` keeps caches/cookies out of the picture.
func stubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [StubURLProtocol.self]
  configuration.timeoutIntervalForRequest = 4
  configuration.timeoutIntervalForResource = 4
  return URLSession(configuration: configuration)
}

/// A request carrying the stub token header so the protocol can find its handler.
func stubbedRequest(token: String, url: URL = URL(string: "https://example.test/thing")!)
  -> URLRequest
{
  var request = URLRequest(url: url)
  request.setValue(token, forHTTPHeaderField: StubURLProtocol.tokenHeader)
  return request
}

/// A thread-safe attempt counter for the "fail N times then succeed" retry stub.
final class AttemptCounter: @unchecked Sendable {
  private let count = OSAllocatedUnfairLock(initialState: 0)
  @discardableResult func increment() -> Int {
    count.withLock {
      $0 += 1
      return $0
    }
  }
  var value: Int { count.withLock { $0 } }
}
