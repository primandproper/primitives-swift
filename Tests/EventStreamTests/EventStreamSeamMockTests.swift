import Foundation
import Testing

@testable import EventStream

@Suite("MockEventStream")
struct MockEventStreamTests {
  @Test("emit pushes events that surface on the events stream, in order")
  func emitsInOrder() async throws {
    let mock = MockEventStream()
    await mock.emit(Event(type: "a"))
    await mock.emit(Event(type: "b"))
    await mock.finish()

    var received: [Event] = []
    for try await event in mock.events { received.append(event) }
    #expect(received == [Event(type: "a"), Event(type: "b")])
  }

  @Test("close records the call and finishes the stream")
  func closeRecords() async throws {
    let mock = MockEventStream()
    #expect(await mock.closeCallCount == 0)
    await mock.close()
    #expect(await mock.closeCallCount == 1)

    var count = 0
    for try await _ in mock.events { count += 1 }
    #expect(count == 0)
  }
}

@Suite("MockBidirectionalEventStream")
struct MockBidirectionalEventStreamTests {
  @Test("records events sent back to the server")
  func recordsSends() async throws {
    let mock = MockBidirectionalEventStream()
    try await mock.send(Event(type: "ping"))
    try await mock.send(Event(type: "pong"))

    #expect(await mock.sentEvents == [Event(type: "ping"), Event(type: "pong")])
  }

  @Test("usable behind the BidirectionalEventStream existential")
  func behindProtocol() async throws {
    let mock = MockBidirectionalEventStream()
    let stream: any BidirectionalEventStream = mock
    try await stream.send(Event(type: "x"))
    await stream.close()
    #expect(await mock.sentEvents.count == 1)
    #expect(await mock.closeCallCount == 1)
  }
}

@Suite("MockEventStreamConnector")
struct MockEventStreamConnectorTests {
  @Test("records connect calls with URL and headers")
  func recordsConnect() async throws {
    let connector = MockEventStreamConnector()
    let url = URL(string: "https://example.test/stream")!
    _ = try await connector.connect(to: url, headers: ["Authorization": "Bearer t"])

    let calls = await connector.connectCalls
    #expect(calls == [MockEventStreamConnector.ConnectCall(url: url, headers: ["Authorization": "Bearer t"])])
  }

  @Test("returns the stream from the injected factory")
  func usesFactory() async throws {
    let stream = MockEventStream()
    let connector = MockEventStreamConnector(stream: { stream })
    let returned = try await connector.connect(to: URL(string: "https://x.test")!)
    #expect(returned is MockEventStream)
    await returned.close()
    #expect(await stream.closeCallCount == 1)
  }
}

@Suite("MockBidirectionalEventStreamConnector")
struct MockBidirectionalEventStreamConnectorTests {
  @Test("records connect calls")
  func recordsConnect() async throws {
    let connector = MockBidirectionalEventStreamConnector()
    let url = URL(string: "wss://example.test/ws")!
    _ = try await connector.connect(to: url)
    #expect(await connector.connectCalls == [
      MockBidirectionalEventStreamConnector.ConnectCall(url: url, headers: [:])
    ])
  }
}

@Suite("NoopWebSocketConnection")
struct NoopWebSocketConnectionTests {
  @Test("send / sendPing / resume / cancel are inert")
  func inert() async throws {
    let conn = NoopWebSocketConnection()
    conn.resume()
    try await conn.send(.string("ignored"))
    try await conn.sendPing()
    conn.cancel(with: .goingAway, reason: nil)
  }

  @Test("receive parks until the surrounding task is cancelled")
  func receiveCancels() async {
    let conn = NoopWebSocketConnection()
    let task = Task { try await conn.receive() }
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
  }
}

@Suite("MockWebSocketConnection")
struct MockWebSocketConnectionMockTests {
  @Test("records resume, sends, and cancel; delivers enqueued messages")
  func recordsAndDelivers() async throws {
    let conn = MockWebSocketConnection()
    conn.resume()
    conn.enqueue(.success(.string("hello")))
    let message = try await conn.receive()
    guard case .string(let text) = message else {
      Issue.record("expected a string message")
      return
    }
    #expect(text == "hello")

    try await conn.send(.string("out"))
    conn.cancel(with: .goingAway, reason: nil)

    #expect(conn.resumeCallCount == 1)
    #expect(conn.sentMessages.count == 1)
    #expect(conn.cancelledWith == .goingAway)
  }
}
