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
/// **Heartbeats.** Go's server proactively pings on `heartbeatInterval` to detect a dead client. A
/// NAT-dropped connection sends neither data nor a close frame, so `receive()` would park forever; this
/// client runs its own heartbeat loop when ``WebSocketEventStreamConfig/heartbeatInterval`` is non-zero,
/// pinging on that interval and tearing the connection down when a pong doesn't come back in time (a
/// peer's *inbound* ping is still auto-answered with a pong by `URLSessionWebSocketTask`; this is the
/// complementary *outbound* liveness check). A zero interval disables the loop.
public actor WebSocketEventStream: BidirectionalEventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let connection: any WebSocketConnection
  private let config: WebSocketEventStreamConfig
  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var receiveTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var closed = false

  /// - Parameter bufferingPolicy: caps how many decoded events buffer for a non-draining consumer before
  ///   the overflow is dropped (see ``BoundedEventStream``). Defaults to Go's 64-slot
  ///   `incomingChannelBuffer` bound.
  init(
    connection: any WebSocketConnection,
    config: WebSocketEventStreamConfig = WebSocketEventStreamConfig(),
    bufferingPolicy: AsyncThrowingStream<Event, any Error>.Continuation.BufferingPolicy =
      .bufferingOldest(EventStreamConfig.defaultBufferSize)
  ) {
    (self.events, self.continuation) = BoundedEventStream.make(bufferingPolicy: bufferingPolicy)
    self.connection = connection
    self.config = config
    self.receiveTask = nil
  }

  /// Resumes the underlying connection and starts the background receive loop (and, when
  /// ``WebSocketEventStreamConfig/heartbeatInterval`` is non-zero, the heartbeat loop). Split out from
  /// `init` because Swift 6 actor initializers cannot store a `Task` that captures `self` (the compiler
  /// treats the capture as "escaping" mid-init); the connector calls this immediately after construction,
  /// once `self` is a fully-initialized actor reference.
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
    if config.heartbeatInterval > .zero {
      heartbeatTask = Task { [weak self] in
        await self?.heartbeatLoop(observer: observer)
      }
    }
  }

  /// Confirms the WebSocket upgrade by sending a ping and awaiting its pong. The connector calls this
  /// right after ``start(observer:)`` so a failed upgrade throws at connect time, rather than being
  /// deferred into a `receive()` that would only surface it once the caller starts reading ``events``.
  func confirmHandshake() async throws {
    try await connection.sendPing()
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

  /// Pings on ``WebSocketEventStreamConfig/heartbeatInterval`` and tears the connection down if a pong
  /// doesn't return within that same interval (the pong-timeout window). This is what turns a silently
  /// NAT-dropped connection — which never errors a parked `receive()` on its own — into an observable
  /// failure, mirroring the intent of Go's server-side heartbeat.
  private func heartbeatLoop(observer: any Observer) async {
    let interval = config.heartbeatInterval
    while !Task.isCancelled {
      do {
        try await Task.sleep(for: interval)
      } catch {
        return  // cancelled via close()
      }
      if Task.isCancelled { return }

      do {
        try await pingAwaitingPong(timeout: interval)
      } catch {
        if closed || Task.isCancelled { return }
        observer.logger.error("websocket heartbeat failed; closing connection", error)
        shutdown(finishing: error)
        return
      }
    }
  }

  /// Sends a ping and waits for its pong, failing with ``EventStreamError/pongTimeout`` if none arrives
  /// within `timeout`. Races the ping against a timeout via a task group so a hung pong can't wedge the
  /// heartbeat loop.
  private func pingAwaitingPong(timeout: Duration) async throws {
    let connection = self.connection
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await connection.sendPing() }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw EventStreamError.pongTimeout
      }
      defer { group.cancelAll() }
      // The first branch to finish decides the outcome: a delivered pong (success) or the timeout/ping
      // error (throw). `cancelAll` then stops the loser.
      try await group.next()
    }
  }

  public func send(_ event: Event) async throws {
    guard !closed else {
      throw EventStreamError.streamClosed
    }
    let data = try encoder.encode(event)
    try await connection.send(.data(data))
  }

  /// Cancels the connection with `.goingAway`, stops the receive and heartbeat loops, and finishes
  /// ``events``. Idempotent.
  public func close() async {
    guard !closed else { return }
    shutdown(finishing: nil)
  }

  /// Shared teardown for both an orderly ``close()`` (`error == nil`) and a heartbeat-detected dead
  /// connection (`error` non-nil, which finishes ``events`` by throwing).
  private func shutdown(finishing error: (any Error)?) {
    guard !closed else { return }
    closed = true
    receiveTask?.cancel()
    heartbeatTask?.cancel()
    connection.cancel(with: .goingAway, reason: nil)
    if let error {
      continuation.finish(throwing: error)
    } else {
      continuation.finish()
    }
  }
}

/// Connects to a WebSocket endpoint, the client analogue of platform-go's `websocket.NewUpgrader`.
public struct WebSocketEventStreamConnector: BidirectionalEventStreamConnector {
  private let observer: any Observer
  /// Builds the underlying connection from the fully-formed request. Defaults to
  /// `session.webSocketTask(with:)`; a test injects a factory that records the request and returns a
  /// fake ``WebSocketConnection`` (there is no `URLProtocol` seam for the WebSocket transport).
  private let makeConnection: @Sendable (URLRequest) -> any WebSocketConnection
  private let bufferSize: Int
  private let config: WebSocketEventStreamConfig

  public init(
    session: URLSession,
    observer: any Observer,
    bufferSize: Int = EventStreamConfig.defaultBufferSize,
    config: WebSocketEventStreamConfig = WebSocketEventStreamConfig()
  ) {
    self.observer = observer
    self.makeConnection = { request in session.webSocketTask(with: request) }
    self.bufferSize = bufferSize
    self.config = config
  }

  /// Test seam: inject the connection factory directly to observe the request custom headers land on.
  init(
    observer: any Observer,
    bufferSize: Int = EventStreamConfig.defaultBufferSize,
    config: WebSocketEventStreamConfig = WebSocketEventStreamConfig(),
    makeConnection: @escaping @Sendable (URLRequest) -> any WebSocketConnection
  ) {
    self.observer = observer
    self.makeConnection = makeConnection
    self.bufferSize = bufferSize
    self.config = config
  }

  public func connect(
    to url: URL, headers: [String: String] = [:]
  ) async throws -> any BidirectionalEventStream {
    try await observer.operation(name: "WebSocket connect") { op in
      op.set(Keys.connectionURL, url.absoluteString)
      var request = URLRequest(url: url)
      for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
      }
      let connection = makeConnection(request)
      let stream = WebSocketEventStream(
        connection: connection, config: config, bufferingPolicy: .bufferingOldest(bufferSize))
      await stream.start(observer: observer)
      // Confirm the upgrade so a failed handshake fails here rather than returning a stream whose
      // receive() only ever errors once the caller starts reading.
      do {
        try await stream.confirmHandshake()
      } catch {
        await stream.close()
        throw op.error(error, "confirming WebSocket handshake")
      }
      return stream
    }
  }
}
