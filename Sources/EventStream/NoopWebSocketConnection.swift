import Foundation

/// A no-op ``WebSocketConnection``: a socket that accepts every call but carries no traffic — the
/// always-safe stand-in for a disabled WebSocket transport, in the spirit of ``NoopEventStream``.
///
/// ``send(_:)`` and ``sendPing()`` succeed silently (a live-looking connection that swallows output),
/// ``resume()`` / ``cancel(with:reason:)`` are inert, and ``receive()`` parks until the surrounding task
/// is cancelled — a connection that never delivers a message, mirroring how ``NoopEventStream`` never
/// yields an event. There is no platform-go analogue; this is a port-native inert conformer added under
/// REPO-05.
public struct NoopWebSocketConnection: WebSocketConnection {
  public init() {}

  public func resume() {}

  public func send(_ message: URLSessionWebSocketTask.Message) async throws {}

  public func sendPing() async throws {}

  public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {}

  /// Never delivers a message: suspends until the surrounding task is cancelled, then throws
  /// `CancellationError`. Backed by a stream that never yields and never finishes, so the suspension is
  /// cancellation-aware (an `AsyncStream` iterator returns `nil` when its task is cancelled).
  public func receive() async throws -> URLSessionWebSocketTask.Message {
    let quiet = AsyncStream<URLSessionWebSocketTask.Message> { _ in }
    for await message in quiet {
      return message
    }
    throw CancellationError()
  }
}
