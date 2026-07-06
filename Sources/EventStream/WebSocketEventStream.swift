import Foundation
import Observability

/// A live ``BidirectionalEventStream``, backed by a `URLSessionWebSocketTask` (injected as
/// ``WebSocketConnection`` so tests can substitute a fake).
///
/// This is the client consumer side of platform-go's `websocket` package: Go's `wsStream`/
/// `bidirectionalWSStream` are the *server's* end of the connection (accepted via `Upgrader.Upgrade`);
/// this is the *client's* end of that same connection, dialed out via `URLSession.webSocketTask(with:)`.
/// Each inbound message is JSON-decoded as a whole ``Event`` (Go's server writes with `conn.WriteJSON`,
/// so the wire payload is one JSON object per frame — unlike SSE, there's no line-oriented framing to
/// parse). ``send(_:)`` is the mirror: JSON-encode an ``Event`` and write it as a single frame.
///
/// A malformed inbound frame is skipped rather than terminating the stream, mirroring Go's
/// `bidirectionalWSStream.readLoop` (`if err = json.Unmarshal(msg, &event); err != nil { continue }`).
///
/// **Heartbeats.** Go's server proactively pings on `heartbeatInterval` to detect a dead client.
/// `URLSessionWebSocketTask` answers an inbound ping with a pong automatically at the transport level,
/// so there is no client-side ping loop to run — see ``WebSocketEventStreamConfig`` for the full note.
public actor WebSocketEventStream: BidirectionalEventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let connection: any WebSocketConnection
  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var receiveTask: Task<Void, Never>?
  private var closed = false

  init(connection: any WebSocketConnection) {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    self.events = AsyncThrowingStream { boundContinuation = $0 }
    self.continuation = boundContinuation
    self.connection = connection
    self.receiveTask = nil
  }

  /// Resumes the underlying connection and starts the background receive loop. Split out from `init`
  /// because Swift 6 actor initializers cannot store a `Task` that captures `self` (the compiler treats
  /// the capture as "escaping" mid-init); the connector calls this immediately after construction, once
  /// `self` is a fully-initialized actor reference.
  func start(observer: any Observer) {
    connection.resume()
    // Tear down the connection and receive loop if the consumer abandons `events` (e.g. breaks out of
    // its `for try await` without calling `close()`, or its consuming task is cancelled). Without this
    // the receive loop keeps awaiting frames and the underlying socket stays live forever. The handler
    // is `@Sendable` and non-isolated, so it hops back onto the actor via an unstructured `Task`.
    continuation.onTermination = { [weak self] _ in
      Task { await self?.close() }
    }
    receiveTask = Task { [weak self] in
      await self?.receiveLoop(observer: observer)
    }
  }

  private func receiveLoop(observer: any Observer) async {
    while !Task.isCancelled {
      let message: URLSessionWebSocketTask.Message
      do {
        message = try await connection.receive()
      } catch {
        if Task.isCancelled {
          break
        }
        continuation.finish(throwing: error)
        return
      }

      let data: Data
      switch message {
      case .data(let value):
        data = value
      case .string(let value):
        data = Data(value.utf8)
      @unknown default:
        continue
      }

      guard let event = try? decoder.decode(Event.self, from: data) else {
        observer.logger.info("skipping malformed event stream message")
        continue
      }
      continuation.yield(event)
    }
    continuation.finish()
  }

  public func send(_ event: Event) async throws {
    guard !closed else {
      throw EventStreamError.streamClosed
    }
    let data = try encoder.encode(event)
    try await connection.send(.data(data))
  }

  /// Cancels the connection with `.goingAway`, stops the receive loop, and finishes ``events``.
  /// Idempotent.
  public func close() async {
    guard !closed else { return }
    closed = true
    receiveTask?.cancel()
    connection.cancel(with: .goingAway, reason: nil)
    continuation.finish()
  }
}

/// Connects to a WebSocket endpoint, the client analogue of platform-go's `websocket.NewUpgrader`.
public struct WebSocketEventStreamConnector: BidirectionalEventStreamConnector {
  private let observer: any Observer
  /// Builds the underlying connection from the fully-formed request. Defaults to
  /// `session.webSocketTask(with:)`; a test injects a factory that records the request and returns a
  /// fake ``WebSocketConnection`` (there is no `URLProtocol` seam for the WebSocket transport).
  private let makeConnection: @Sendable (URLRequest) -> any WebSocketConnection

  public init(session: URLSession, observer: any Observer) {
    self.observer = observer
    self.makeConnection = { request in session.webSocketTask(with: request) }
  }

  /// Test seam: inject the connection factory directly to observe the request custom headers land on.
  init(
    observer: any Observer,
    makeConnection: @escaping @Sendable (URLRequest) -> any WebSocketConnection
  ) {
    self.observer = observer
    self.makeConnection = makeConnection
  }

  public func connect(
    to url: URL, headers: [String: String] = [:]
  ) async throws -> any BidirectionalEventStream {
    await observer.operation(name: "WebSocket connect") { op in
      op.set(Keys.connectionURL, url.absoluteString)
      var request = URLRequest(url: url)
      for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
      }
      let connection = makeConnection(request)
      let stream = WebSocketEventStream(connection: connection)
      await stream.start(observer: observer)
      return stream
    }
  }
}
