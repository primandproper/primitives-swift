import Foundation
import Testing

@testable import EventStream

@Suite("NoopEventStream")
struct NoopEventStreamTests {
  @Test("events finishes with no elements once close is called, mirroring Go's Done() on Close")
  func finishesOnClose() async throws {
    let stream = NoopEventStream()
    await stream.close()

    var iterator = stream.events.makeAsyncIterator()
    let next = try await iterator.next()
    #expect(next == nil)
  }

  @Test("close is idempotent")
  func closeIsIdempotent() async {
    let stream = NoopEventStream()
    await stream.close()
    await stream.close()
  }
}

@Suite("NoopBidirectionalEventStream")
struct NoopBidirectionalEventStreamTests {
  @Test("send returns without throwing, mirroring Go's Send returning nil unconditionally")
  func sendReturnsWithoutThrowing() async throws {
    let stream = NoopBidirectionalEventStream()
    try await stream.send(Event(type: "test", payload: Data(#"{"key":"value"}"#.utf8)))
  }

  @Test("events finishes with no elements once close is called")
  func finishesOnClose() async throws {
    let stream = NoopBidirectionalEventStream()
    await stream.close()

    var iterator = stream.events.makeAsyncIterator()
    let next = try await iterator.next()
    #expect(next == nil)
  }

  @Test("close is idempotent")
  func closeIsIdempotent() async {
    let stream = NoopBidirectionalEventStream()
    await stream.close()
    await stream.close()
  }
}

@Suite("Noop connectors")
struct NoopConnectorTests {
  @Test("NoopEventStreamConnector returns a usable NoopEventStream")
  func noopEventStreamConnectorReturnsUsableStream() async throws {
    let connector = NoopEventStreamConnector()
    let stream = try await connector.connect(to: URL(string: "https://example.test/events")!)

    await stream.close()
  }

  @Test("NoopBidirectionalEventStreamConnector returns a usable NoopBidirectionalEventStream")
  func noopBidirectionalConnectorReturnsUsableStream() async throws {
    let connector = NoopBidirectionalEventStreamConnector()
    let stream = try await connector.connect(to: URL(string: "wss://example.test/events")!)

    try await stream.send(Event(type: "test"))
    await stream.close()
  }
}
