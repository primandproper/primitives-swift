import Foundation
import Observability
import Retry
import Testing
import os

@testable import EventStream

/// Builds a live ``SSEEventStream`` over a controlled throwing byte source: `text` is fed in full, then
/// the source ends per `ending`. A `.park` source never ends, so the returned stream keeps its (retained)
/// continuation alive via `parkedContinuations` and only finishes when the stream is closed.
private enum Ending {
  case clean
  case error(any Error & Sendable)
  case park
}

/// Retains continuations for `.park` sources so they aren't finished by deallocation mid-test.
private let parkedContinuations =
  OSAllocatedUnfairLock<[AsyncThrowingStream<UInt8, any Error>.Continuation]>(initialState: [])

private func liveSSEStream(_ text: String, _ ending: Ending) async -> SSEEventStream {
  let (bytes, continuation) = AsyncThrowingStream<UInt8, any Error>.makeStream()
  for byte in text.utf8 { continuation.yield(byte) }
  switch ending {
  case .clean:
    continuation.finish()
  case .error(let error):
    continuation.finish(throwing: error)
  case .park:
    parkedContinuations.withLock { $0.append(continuation) }
  }
  let stream = SSEEventStream()
  await stream.start(bytes: bytes, networkTask: nil, observer: recordingObserver("test"))
  return stream
}

@Suite("ReconnectingSSEEventStream")
struct ReconnectingSSEEventStreamTests {
  @Test("a mid-stream transport blip reconnects instead of killing the stream", .timeLimit(.minutes(1)))
  func reconnectsAfterTransportBlip() async throws {
    let connectCount = OSAllocatedUnfairLock(initialState: 0)
    let capturedHeaders = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    let connect: @Sendable ([String: String]) async throws -> SSEEventStream = { headers in
      let attempt = connectCount.withLock { $0 += 1; return $0 }
      capturedHeaders.withLock { $0 = headers }
      if attempt == 1 {
        // First connection: yield event A carrying id 42, then a transport error.
        return await liveSSEStream(
          "id: 42\nevent: A\ndata: {}\n\n", .error(URLError(.networkConnectionLost)))
      }
      // Subsequent connections: yield event B, then park (so the stream doesn't spin re-dialing).
      return await liveSSEStream("event: B\ndata: {}\n\n", .park)
    }

    let stream = ReconnectingSSEEventStream(
      retryPolicy: NoopRetryPolicy(),
      reconnectDelay: .milliseconds(1),
      observer: recordingObserver("test"),
      connect: connect)
    await stream.start()
    defer { Task { await stream.close() } }

    var iterator = stream.events.makeAsyncIterator()
    let first = try #require(try await iterator.next())
    #expect(first.type == "A")

    // The transport blip did not terminate the stream: a second event arrives from the re-dialed
    // connection.
    let second = try #require(try await iterator.next())
    #expect(second.type == "B")

    // The re-dial resumed with the last-seen event id, per the WHATWG reconnection model.
    #expect(capturedHeaders.withLock { $0["Last-Event-ID"] } == "42")
    #expect(connectCount.withLock { $0 } >= 2)
  }

  @Test("close ends reconnection for good", .timeLimit(.minutes(1)))
  func closeEndsReconnection() async throws {
    let connect: @Sendable ([String: String]) async throws -> SSEEventStream = { _ in
      await liveSSEStream("event: tick\ndata: {}\n\n", .park)
    }

    let stream = ReconnectingSSEEventStream(
      retryPolicy: NoopRetryPolicy(),
      reconnectDelay: .milliseconds(1),
      observer: recordingObserver("test"),
      connect: connect)
    await stream.start()

    var iterator = stream.events.makeAsyncIterator()
    let event = try #require(try await iterator.next())
    #expect(event.type == "tick")

    await stream.close()
    let next = try await iterator.next()
    #expect(next == nil)
  }
}
