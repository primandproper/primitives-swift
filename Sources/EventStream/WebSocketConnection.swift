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
  /// Sends a WebSocket ping and completes when its pong arrives (or throws if the ping/pong fails).
  /// ``WebSocketEventStream`` uses this both to confirm the handshake at connect time and to drive the
  /// heartbeat that detects a NAT-dropped connection — a `receive()` alone parks forever on such a
  /// connection, since a dead peer sends neither data nor a close frame.
  func sendPing() async throws
  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: WebSocketConnection {
  /// Bridges `URLSessionWebSocketTask.sendPing(pongReceiveHandler:)`'s completion handler into the async
  /// seam: the pong handler fires with `nil` on a received pong and with an error otherwise.
  public func sendPing() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      self.sendPing { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}
