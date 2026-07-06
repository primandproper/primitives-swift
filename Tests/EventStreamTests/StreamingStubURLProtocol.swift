import Foundation
import os

/// A hermetic `URLProtocol` stub that can deliver its response body across several `didLoad` calls
/// over time, so a test can drive `URLSession.bytes(for:)`'s progressive delivery without a live
/// network — the SSE analogue of `HTTPClientTests`' single-shot `StubURLProtocol`.
///
/// The stub token travels in an `X-Stub-Token` request *header*, which doubles as proof that
/// ``SSEEventStreamConnector/connect(to:headers:)`` actually delivers caller headers onto the outbound
/// request: if the header didn't arrive, routing would fail and the stub would 400. Tests can also read
/// back every header the request carried via ``receivedHeaders(for:)``.
final class StreamingStubURLProtocol: URLProtocol, @unchecked Sendable {
  static let tokenHeader = "X-Stub-Token"

  enum Completion: Sendable {
    case finish
    case fail(any Error & Sendable)
    /// Never calls back until `stopLoading` (i.e. the consuming `Task` is cancelled), at which point
    /// a `URLError.cancelled` is reported — proving a local `close()` actually tears down the network
    /// read rather than leaving it running.
    case hangUntilCancelled
  }

  struct Behavior: Sendable {
    var status: Int
    var chunks: [(delay: Duration, data: Data)]
    var completion: Completion

    init(
      status: Int = 200, chunks: [(delay: Duration, data: Data)] = [],
      completion: Completion = .finish
    ) {
      self.status = status
      self.chunks = chunks
      self.completion = completion
    }
  }

  private static let registry =
    OSAllocatedUnfairLock<[String: Behavior]>(initialState: [:])

  /// Every request header the stub saw for a given token, recorded in `startLoading` so a test can
  /// assert exactly which headers ``SSEEventStreamConnector`` put on the wire.
  private static let receivedHeadersByToken =
    OSAllocatedUnfairLock<[String: [String: String]]>(initialState: [:])

  static func register(_ token: String, _ behavior: Behavior) {
    registry.withLock { $0[token] = behavior }
  }

  static func unregister(_ token: String) {
    registry.withLock { $0[token] = nil }
    receivedHeadersByToken.withLock { $0[token] = nil }
  }

  static func receivedHeaders(for token: String) -> [String: String]? {
    receivedHeadersByToken.withLock { $0[token] }
  }

  private static func token(for request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: tokenHeader)
  }

  private let parkedForCancellation = OSAllocatedUnfairLock(initialState: false)

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard
      let token = Self.token(for: request),
      let behavior = Self.registry.withLock({ $0[token] })
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    Self.receivedHeadersByToken.withLock { $0[token] = request.allHTTPHeaderFields ?? [:] }

    // Mark "parked" synchronously, before any async hop, when there's nothing to deliver first: a
    // `.hangUntilCancelled` behavior with no chunks can otherwise race a same-tick `close()` against the
    // async Task below actually running, leaving `stopLoading` seeing `parkedForCancellation == false`
    // and silently doing nothing (the connection then only ever ends via the session's own timeout).
    if case .hangUntilCancelled = behavior.completion, behavior.chunks.isEmpty {
      parkedForCancellation.withLock { $0 = true }
    }

    let response = HTTPURLResponse(
      url: request.url!, statusCode: behavior.status, httpVersion: "HTTP/1.1", headerFields: [:])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

    Task {
      for (delay, data) in behavior.chunks {
        if delay > .zero {
          try? await Task.sleep(for: delay)
        }
        self.client?.urlProtocol(self, didLoad: data)
      }

      // A short grace period before completing/failing, so a chunk just handed to `didLoad` above has
      // a chance to actually flush into the consumer's `AsyncBytes` before the connection ends —
      // otherwise a same-tick completion can race ahead of delivery and the chunk is never observed.
      try? await Task.sleep(for: .milliseconds(5))

      switch behavior.completion {
      case .finish:
        self.client?.urlProtocolDidFinishLoading(self)
      case .fail(let error):
        self.client?.urlProtocol(self, didFailWithError: error)
      case .hangUntilCancelled:
        self.parkedForCancellation.withLock { $0 = true }
      }
    }
  }

  override func stopLoading() {
    if parkedForCancellation.withLock({ $0 }) {
      client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
  }
}

/// A `URLSession` wired to ``StreamingStubURLProtocol``. `.ephemeral` keeps caches/cookies out of it.
func streamingStubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [StreamingStubURLProtocol.self]
  configuration.timeoutIntervalForRequest = 4
  configuration.timeoutIntervalForResource = 4
  return URLSession(configuration: configuration)
}

/// The endpoint every stubbed connection dials. Routing is by header (see `stubRoutingHeaders`), not
/// by URL, so a single fixed URL serves every test.
func streamingStubbedURL() -> URL {
  URL(string: "https://example.test/events")!
}

/// The header set that routes a stubbed request to `token`'s registered behavior — passed to
/// ``SSEEventStreamConnector/connect(to:headers:)`` so the token rides the same header channel real
/// auth headers would.
func stubRoutingHeaders(token: String) -> [String: String] {
  [StreamingStubURLProtocol.tokenHeader: token]
}
