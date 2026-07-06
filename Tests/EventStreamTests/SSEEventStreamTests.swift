import Foundation
import Observability
import Testing

@testable import EventStream

/// Feeds `string`'s UTF-8 bytes into a fresh `AsyncStream<UInt8>`, leaving the continuation open (not
/// finished) so a test can simulate a still-open connection and later decide whether to finish it.
private func openByteStream(_ string: String) -> (
  stream: AsyncStream<UInt8>, continuation: AsyncStream<UInt8>.Continuation
) {
  let (stream, continuation) = AsyncStream<UInt8>.makeStream()
  for byte in string.utf8 {
    continuation.yield(byte)
  }
  return (stream, continuation)
}

@Suite("SSEEventStream (hermetic, fake byte source)")
struct SSEEventStreamHermeticTests {
  @Test("dispatches an event once its frame is fully fed in")
  func dispatchesEventOnceFrameComplete() async throws {
    let (bytes, continuation) = openByteStream("event: first\ndata: {\"n\":1}\n\n")
    continuation.finish()

    let stream = SSEEventStream()
    await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "first")
    #expect(event.payload == Data(#"{"n":1}"#.utf8))
  }

  @Test("events finishes once the byte source finishes")
  func finishesWhenByteSourceFinishes() async throws {
    let (bytes, continuation) = openByteStream("event: only\ndata: {}\n\n")
    continuation.finish()

    let stream = SSEEventStream()
    await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "only")

    let next = try await iterator.next()
    #expect(next == nil)
  }

  @Test(
    "close() finishes events immediately even while the byte source is still open",
    .timeLimit(.minutes(1)))
  func closeFinishesEventsWhileByteSourceStillOpen() async throws {
    // The byte source never finishes on its own (simulating a connection with no end in sight); this
    // proves close() doesn't wait on the network layer to finish `events` — the exact case a live
    // `URLSession`/`URLProtocol` stub can't reliably exercise (see SSEEventStreamConnectorTests's doc
    // comment for why the network-backed suite doesn't attempt this scenario).
    let (bytes, _) = openByteStream("")

    let stream = SSEEventStream()
    await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))

    await stream.close()

    var iterator = stream.events.makeAsyncIterator()
    let next = try await iterator.next()
    #expect(next == nil)
  }

  @Test("close is idempotent")
  func closeIsIdempotent() async {
    let (bytes, _) = openByteStream("")
    let stream = SSEEventStream()
    await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))

    await stream.close()
    await stream.close()
  }

  @Test(
    "a transport error partway through the byte source surfaces to the consumer",
    .timeLimit(.minutes(1)))
  func midStreamTransportErrorSurfaces() async throws {
    // A throwing byte source models a connection that delivers a complete frame and then drops mid-stream
    // — the hermetic analogue of `URLSession.AsyncBytes` erroring an iteration after some body has arrived.
    // The first event must be delivered, and the injected transport error must then surface from the next
    // `next()`, finishing `events` by throwing rather than silently ending it.
    let (bytes, continuation) = AsyncThrowingStream<UInt8, any Error>.makeStream()
    for byte in "event: first\ndata: {\"n\":1}\n\n".utf8 {
      continuation.yield(byte)
    }

    let stream = SSEEventStream()
    await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))
    defer { Task { await stream.close() } }

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "first")

    // The connection now fails partway through the stream; the buffered frame was already drained above,
    // so this terminal error is the next thing the pump sees.
    continuation.finish(throwing: URLError(.networkConnectionLost))

    await #expect(throws: (any Error).self) {
      _ = try await iterator.next()
    }
  }

  @Test(
    "abandoning the consumer tears down the pump loop via events.onTermination",
    .timeLimit(.minutes(1)))
  func abandoningConsumerTearsDownPump() async throws {
    // A never-finishing byte source: without an `onTermination` handler on `events`, cancelling the
    // consuming task would leave the pump iterating these bytes (and, in production, the URLSessionTask
    // live) forever. The byte source's own `onTermination` fires only when the pump loop is torn down,
    // so awaiting it proves the abandoned consumer reaped the read loop.
    let (bytes, _byteContinuation) = AsyncStream<UInt8>.makeStream()
    let (torndown, torndownContinuation) = AsyncStream<Void>.makeStream()
    _byteContinuation.onTermination = { _ in
      torndownContinuation.yield(())
      torndownContinuation.finish()
    }

    let stream = SSEEventStream()
    await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))

    let consumer = Task {
      for try await _ in stream.events {}
    }
    consumer.cancel()

    var iterator = torndown.makeAsyncIterator()
    let fired: Void? = await iterator.next()
    #expect(fired != nil)
  }
}

@Suite("SSEEventStreamConnector (live loopback, no real network)")
struct SSEEventStreamConnectorTests {
  // These tests drive `URLSession.bytes(for:)` through a `URLProtocol` stub. Empirically, in this
  // toolchain that API only returns (or throws) once the *entire* request lifecycle finishes — it does
  // not surface a response early and stream the body progressively the way real network requests do, and
  // a `URLSessionTask.cancel()` does not reliably invoke the stub's `stopLoading()` before the
  // configured timeout. Both are transport/test-harness characteristics of this sandbox, not properties
  // of `SSEEventStreamConnector`/`SSEEventStream`. So this suite covers what's reliably observable here
  // (a complete round trip, byte-level chunk-boundary handling, and error propagation); the progressive-
  // delivery and close()-while-open scenarios are covered hermetically instead, in
  // `SSEEventStreamHermeticTests` above, via a fake byte source this toolchain quirk doesn't affect.

  @Test("a complete SSE response decodes into its events")
  func completeResponseDecodesEvents() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(
      token,
      .init(chunks: [
        (delay: .zero, data: Data("event: first\ndata: {\"n\":1}\n\n".utf8)),
        (delay: .zero, data: Data("event: second\ndata: {\"n\":2}\n\n".utf8)),
      ]))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))
    let stream = try await connector.connect(
      to: streamingStubbedURL(), headers: stubRoutingHeaders(token: token))
    defer { Task { await stream.close() } }

    var received: [Event] = []
    for try await event in stream.events {
      received.append(event)
    }

    #expect(received.map(\.type) == ["first", "second"])
    #expect(
      received.map { String(decoding: $0.payload ?? Data(), as: UTF8.self) } == [
        #"{"n":1}"#, #"{"n":2}"#,
      ])
  }

  @Test("a line split across two network chunks still parses as one event")
  func lineSplitAcrossChunksStillParses() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(
      token,
      .init(chunks: [
        (delay: .zero, data: Data("event: sp".utf8)),
        (delay: .zero, data: Data("lit\ndata: {}\n\n".utf8)),
      ]))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))
    let stream = try await connector.connect(
      to: streamingStubbedURL(), headers: stubRoutingHeaders(token: token))
    defer { Task { await stream.close() } }

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "split")
  }

  @Test("a transport failure propagates as a thrown error")
  func transportFailurePropagates() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(
      token,
      .init(
        chunks: [(delay: .zero, data: Data("event: ok\ndata: {}\n\n".utf8))],
        completion: .fail(URLError(.networkConnectionLost))))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))

    // With a proper `text/event-stream` Content-Type, URLSession delivers the body progressively, so a
    // mid-body transport failure surfaces while iterating `events` rather than from `connect()`. Draining
    // the stream catches it wherever it lands.
    await #expect(throws: (any Error).self) {
      let stream = try await connector.connect(
        to: streamingStubbedURL(), headers: stubRoutingHeaders(token: token))
      for try await _ in stream.events {}
    }
  }

  @Test("custom headers reach the outbound request, and Accept is not clobbered")
  func customHeadersReachRequestWithoutClobberingAccept() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(
      token, .init(chunks: [(delay: .zero, data: Data("event: ok\ndata: {}\n\n".utf8))]))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))
    // A caller-supplied Authorization rides along; a caller-supplied Accept must lose to the SSE
    // content-type the stream depends on. (`stubRoutingHeaders` also proves the token header — the
    // routing itself — arrived, since a missing header would 400 before any stream is returned.)
    let stream = try await connector.connect(
      to: streamingStubbedURL(),
      headers: stubRoutingHeaders(token: token).merging(
        ["Authorization": "Bearer secret-token", "Accept": "application/json"]
      ) { _, new in new })
    defer { Task { await stream.close() } }

    // Drain so `startLoading` has definitely recorded the request.
    for try await _ in stream.events {}

    let received = try #require(StreamingStubURLProtocol.receivedHeaders(for: token))
    func header(_ name: String) -> String? {
      received.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    #expect(header("Authorization") == "Bearer secret-token")
    #expect(header("Accept") == "text/event-stream")
  }

  @Test("a non-2xx response throws connectionFailed instead of returning a stream")
  func nonSuccessStatusThrows() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(token, .init(status: 503))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))

    await #expect(throws: EventStreamError.connectionFailed(status: 503)) {
      _ = try await connector.connect(
        to: streamingStubbedURL(), headers: stubRoutingHeaders(token: token))
    }
  }

  @Test("a 200 with a non-event-stream Content-Type is rejected instead of parsed as silence")
  func wrongContentTypeRejected() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(
      token,
      .init(
        contentType: "text/html",
        chunks: [(delay: .zero, data: Data("<html>error</html>".utf8))]))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))

    await #expect(throws: EventStreamError.invalidContentType(received: "text/html")) {
      _ = try await connector.connect(
        to: streamingStubbedURL(), headers: stubRoutingHeaders(token: token))
    }
  }

  @Test("a Content-Type with charset parameters is still accepted")
  func contentTypeWithParametersAccepted() async throws {
    let token = UUID().uuidString
    StreamingStubURLProtocol.register(
      token,
      .init(
        contentType: "text/event-stream; charset=utf-8",
        chunks: [(delay: .zero, data: Data("event: ok\ndata: {}\n\n".utf8))]))
    defer { StreamingStubURLProtocol.unregister(token) }

    let connector = SSEEventStreamConnector(
      session: streamingStubbedSession(), observer: recordingObserver("test"))
    let stream = try await connector.connect(
      to: streamingStubbedURL(), headers: stubRoutingHeaders(token: token))
    defer { Task { await stream.close() } }

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "ok")
  }
}

@Suite("StreamingSession factory")
struct StreamingSessionTests {
  @Test("disables the resource timeout and raises the inter-byte idle window")
  func configurationValues() {
    let configuration = StreamingSession.configuration()
    // Resource timeout disabled: URLSessionConfiguration.default's finite ceiling would otherwise kill a
    // long-lived stream regardless of activity.
    #expect(configuration.timeoutIntervalForResource == .infinity)
    // Request timeout is the inter-byte idle window for a streaming body; raised well past the 60s
    // default so a quiet stream isn't torn down.
    #expect(configuration.timeoutIntervalForRequest == StreamingSession.interByteIdleTimeout)
    #expect(configuration.timeoutIntervalForRequest > 60)
  }
}
