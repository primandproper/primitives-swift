import Foundation

/// The slice of `URLSessionWebSocketTask` ``WebSocketEventStream`` needs, extracted as a protocol.
///
/// `URLSessionWebSocketTask` is a concrete, non-mockable class — unlike plain HTTP, `URLProtocol`
/// cannot intercept the WebSocket transport, so ``HTTPClient``'s "inject a stubbed `URLSession`" trick
/// doesn't apply here. This mirrors the same "local protocol seam over an unstable/untestable
/// dependency" move ``HTTPClient/CircuitBreaker`` makes: the real task conforms below with zero code,
/// and tests inject a fake conformer to drive ``WebSocketEventStream``'s state machine without a
/// network.
public protocol WebSocketConnection: Sendable {
  func resume()
  func send(_ message: URLSessionWebSocketTask.Message) async throws
  func receive() async throws -> URLSessionWebSocketTask.Message
  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: WebSocketConnection {}
