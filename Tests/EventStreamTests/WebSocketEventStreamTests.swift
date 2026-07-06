import Foundation
import Observability
import Testing
import os

@testable import EventStream

@Suite("WebSocketEventStream")
struct WebSocketEventStreamTests {
  @Test("start resumes the underlying connection")
  func startResumesConnection() async {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))

    #expect(connection.resumeCallCount == 1)

    await stream.close()
  }

  @Test("decodes an inbound JSON data frame as an Event")
  func decodesDataFrame() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    let encoded = try JSONEncoder().encode(Event(type: "hello", payload: Data(#"{"n":1}"#.utf8)))
    connection.enqueue(.success(.data(encoded)))

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "hello")
    #expect(event.payload == Data(#"{"n":1}"#.utf8))
  }

  @Test("decodes an inbound JSON text frame the same as a data frame")
  func decodesTextFrame() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    connection.enqueue(.success(.string(#"{"type":"ping"}"#)))

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "ping")
  }

  @Test("skips an unparseable message and continues, mirroring Go's readLoop")
  func skipsMalformedMessages() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    connection.enqueue(.success(.string("this is not json")))
    connection.enqueue(.success(.string(#"{"type":"good"}"#)))

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "good")
  }

  @Test("a transport failure from receive() finishes the stream by throwing")
  func transportFailureFinishesByThrowing() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    connection.enqueue(.failure(URLError(.networkConnectionLost)))

    var iterator = stream.events.makeAsyncIterator()
    await #expect(throws: (any Error).self) {
      _ = try await iterator.next()
    }
  }

  @Test("send JSON-encodes the event and forwards it to the connection")
  func sendEncodesAndForwards() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    let event = Event(type: "outbound", payload: Data(#"{"x":1}"#.utf8))
    try await stream.send(event)

    #expect(connection.sentMessages.count == 1)
    guard case .data(let sentData) = connection.sentMessages[0] else {
      Issue.record("expected a .data message")
      return
    }
    let decoded = try JSONDecoder().decode(Event.self, from: sentData)
    #expect(decoded == event)
  }

  @Test("send throws streamClosed after close, mirroring Go's post-Close Send error")
  func sendThrowsAfterClose() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    await stream.close()

    await #expect(throws: EventStreamError.streamClosed) {
      try await stream.send(Event(type: "too-late"))
    }
  }

  @Test(
    "close cancels the connection with .goingAway and finishes events",
    .timeLimit(.minutes(1)))
  func closeCancelsConnectionAndFinishesEvents() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))

    await stream.close()

    #expect(connection.cancelledWith == .goingAway)

    var iterator = stream.events.makeAsyncIterator()
    let next = try await iterator.next()
    #expect(next == nil)
  }

  @Test("close is idempotent")
  func closeIsIdempotent() async {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))

    await stream.close()
    await stream.close()
  }

  @Test(
    "abandoning the consumer tears down the connection via events.onTermination",
    .timeLimit(.minutes(1)))
  func abandoningConsumerCancelsConnection() async throws {
    // Without an `onTermination` handler on `events`, cancelling the consuming task would leave the
    // receive loop awaiting frames and the socket live forever. onTermination hops to the actor and
    // runs close(), which cancels the connection with `.goingAway`.
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))

    let consumer = Task {
      for try await _ in stream.events {}
    }
    consumer.cancel()

    // Wait for the onTermination-driven close() to reach the connection.
    while connection.cancelledWith == nil {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(connection.cancelledWith == .goingAway)
  }

  @Test("confirmHandshake succeeds when the initial ping is answered")
  func confirmHandshakeSucceeds() async throws {
    let connection = FakeWebSocketConnection()  // defaults to answering pings with a pong
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    try await stream.confirmHandshake()
    #expect(connection.pingCallCount == 1)
  }

  @Test("confirmHandshake propagates a failed upgrade instead of deferring it to receive()")
  func confirmHandshakeFailurePropagates() async throws {
    let connection = FakeWebSocketConnection()
    connection.setPingResponse(.failure(URLError(.badServerResponse)))
    let stream = WebSocketEventStream(connection: connection)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    await #expect(throws: (any Error).self) {
      try await stream.confirmHandshake()
    }
  }

  @Test("the heartbeat sends pings on the configured interval", .timeLimit(.minutes(1)))
  func heartbeatSendsPings() async throws {
    let connection = FakeWebSocketConnection()  // pings answered with a pong
    let config = WebSocketEventStreamConfig(heartbeatInterval: .milliseconds(20))
    let stream = WebSocketEventStream(connection: connection, config: config)
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    // Poll until at least two heartbeats have fired, proving the loop is periodic rather than one-shot.
    for _ in 0..<100 {
      if connection.pingCallCount >= 2 { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(connection.pingCallCount >= 2)
  }

  @Test("a pong timeout tears the connection down", .timeLimit(.minutes(1)))
  func pongTimeoutClosesConnection() async throws {
    let connection = FakeWebSocketConnection()
    connection.setPingResponse(.hang)  // ping is sent but no pong ever comes back
    let config = WebSocketEventStreamConfig(heartbeatInterval: .milliseconds(20))
    let stream = WebSocketEventStream(connection: connection, config: config)
    await stream.start(observer: recordingObserver("test"))

    // A NAT-dropped connection never errors a parked receive() on its own; the heartbeat's pong timeout
    // is what surfaces it, finishing events by throwing and cancelling the connection.
    var iterator = stream.events.makeAsyncIterator()
    await #expect(throws: (any Error).self) {
      _ = try await iterator.next()
    }
    #expect(connection.cancelledWith == .goingAway)
  }

  @Test("a zero heartbeat interval runs no heartbeat loop")
  func zeroHeartbeatIntervalDisablesLoop() async throws {
    let connection = FakeWebSocketConnection()
    let stream = WebSocketEventStream(connection: connection)  // default config: interval .zero
    await stream.start(observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    try await Task.sleep(for: .milliseconds(40))
    #expect(connection.pingCallCount == 0)
  }
}

@Suite("WebSocketEventStreamConnector")
struct WebSocketEventStreamConnectorTests {
  @Test("custom headers are set on the request used to build the connection")
  func customHeadersReachRequest() async throws {
    let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
    let connector = WebSocketEventStreamConnector(observer: recordingObserver("test")) { request in
      captured.withLock { $0 = request }
      return FakeWebSocketConnection()
    }

    let stream = try await connector.connect(
      to: URL(string: "wss://example.test/events")!,
      headers: ["Authorization": "Bearer secret-token", "X-Custom": "on"])
    defer { Task { await stream.close() } }

    let request = try #require(captured.withLock { $0 })
    #expect(request.url == URL(string: "wss://example.test/events")!)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    #expect(request.value(forHTTPHeaderField: "X-Custom") == "on")
  }

  @Test("connect without headers still builds a request for the URL")
  func noHeadersStillBuildsRequest() async throws {
    let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
    let connector = WebSocketEventStreamConnector(observer: recordingObserver("test")) { request in
      captured.withLock { $0 = request }
      return FakeWebSocketConnection()
    }

    let stream = try await connector.connect(to: URL(string: "wss://example.test/events")!)
    defer { Task { await stream.close() } }

    let request = try #require(captured.withLock { $0 })
    #expect(request.url == URL(string: "wss://example.test/events")!)
    #expect(request.allHTTPHeaderFields?.isEmpty ?? true)
  }
}
