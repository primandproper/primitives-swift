import Foundation
import os

/// The canned outcome a stubbed request produces when it reaches ``StubURLProtocol``.
///
/// Mirrors the ad-hoc `StubOutcome`/`LLMStubOutcome` enums that several test targets in this package
/// grew independently (`HTTPClientTests`, `LLMTests`, `EventStreamTests`); this is the canonical shape
/// they can all share.
public enum StubbedResponse: Sendable {
  /// Deliver an `HTTPURLResponse` with `status`, `headers`, and `body`, then finish loading.
  case success(status: Int, body: Data, headers: [String: String])
  /// Fail the request with `error` (e.g. a `URLError`), simulating a transport failure.
  case failure(any Error & Sendable)

  /// A `200 OK` response carrying `body` and the given `headers`.
  public static func ok(body: Data = Data(), headers: [String: String] = [:]) -> StubbedResponse {
    .success(status: 200, body: body, headers: headers)
  }
}

/// The canonical hermetic `URLProtocol` stub for this package's tests, so a test never touches the
/// network. It adapts the intent of platform-go's `testutils.BuildTestRequest` (deterministic,
/// injectable request/response plumbing) to `URLSession`.
///
/// Handlers are keyed by a per-request token carried in the ``tokenHeader`` header, not by a single
/// global handler, so parallel `swift-testing` cases can't clobber each other's stubs. Each test
/// registers a handler under a unique token, points its requests at that token (see ``request(token:url:)``),
/// and unregisters on the way out. Every request the stub sees is recorded so a test can assert on the
/// request it actually sent (method, headers, body) after the fact — the generalization of the
/// hand-rolled `CapturedRequest` boxes the LLM tests used.
public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  /// The header a request carries to route itself to a registered handler.
  public static let tokenHeader = "X-TestSupport-Stub-Token"

  private struct Registration {
    var handler: @Sendable (URLRequest) -> StubbedResponse
    var captured: [URLRequest] = []
  }

  private static let registry = OSAllocatedUnfairLock<[String: Registration]>(initialState: [:])

  /// Registers `handler` to answer any request tagged with `token`. Replaces a prior registration for
  /// the same token and clears its captured requests.
  public static func register(
    token: String, handler: @escaping @Sendable (URLRequest) -> StubbedResponse
  ) {
    registry.withLock { $0[token] = Registration(handler: handler) }
  }

  /// Registers a handler that always returns `response` for `token`, ignoring the request.
  public static func register(token: String, response: StubbedResponse) {
    register(token: token) { _ in response }
  }

  /// Removes the handler and captured requests for `token`.
  public static func unregister(token: String) {
    registry.withLock { $0[token] = nil }
  }

  /// The requests the stub has seen for `token`, in order, since it was registered.
  public static func capturedRequests(token: String) -> [URLRequest] {
    registry.withLock { $0[token]?.captured ?? [] }
  }

  private static func recordAndHandle(_ request: URLRequest, token: String) -> StubbedResponse? {
    registry.withLock {
      guard var registration = $0[token] else { return nil }
      registration.captured.append(request)
      $0[token] = registration
      return registration.handler(request)
    }
  }

  public override class func canInit(with request: URLRequest) -> Bool { true }
  public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  public override func startLoading() {
    guard
      let token = request.value(forHTTPHeaderField: StubURLProtocol.tokenHeader),
      let outcome = StubURLProtocol.recordAndHandle(request, token: token)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    switch outcome {
    case .success(let status, let body, let headers):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  public override func stopLoading() {}

  // MARK: - Session / request plumbing

  /// A `URLSession` wired to this stub. `.ephemeral` keeps caches and cookies out of the picture, and
  /// the short timeouts keep a misconfigured test from hanging.
  public static func makeSession(timeout: TimeInterval = 4) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    return URLSession(configuration: configuration)
  }

  /// A `URLRequest` carrying `token` in ``tokenHeader`` so the stub can find its handler.
  public static func request(
    token: String, url: URL = URL(string: "https://example.test/thing")!
  ) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: tokenHeader)
    return request
  }

  /// Reads a request's body, transparently draining `httpBodyStream` — `URLSession` converts an
  /// `httpBody` into a stream by the time a `URLProtocol` sees the request, so `request.httpBody` is
  /// often nil for a captured request.
  public static func body(of request: URLRequest) -> Data {
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
}
