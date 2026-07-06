import Foundation
import Testing

@testable import EventStream

/// Yields `count` `Event`s of type `e1…eN` into `continuation` without draining, then finishes it, and
/// returns everything the stream ultimately delivers. The producer runs to completion *before* the sole
/// consumer reads, so the `BufferingPolicy`'s drop behavior is exercised deterministically (no race
/// between yielding and draining).
private func drainAfterOvershoot(
  policy: AsyncThrowingStream<Event, any Error>.Continuation.BufferingPolicy,
  count: Int
) async throws -> [String] {
  let (stream, continuation) = BoundedEventStream.make(bufferingPolicy: policy)
  for n in 1...count {
    continuation.yield(Event(type: "e\(n)"))
  }
  continuation.finish()

  var received: [String] = []
  for try await event in stream {
    received.append(event.type)
  }
  return received
}

@Suite("BoundedEventStream buffering policy")
struct BoundedEventStreamTests {
  @Test(
    "bufferingOldest keeps the oldest events and drops the overflow from a non-draining consumer")
  func bufferingOldestKeepsOldest() async throws {
    // Five events overshoot a 2-slot buffer; e1,e2 fill it and e3–e5 are dropped.
    let received = try await drainAfterOvershoot(policy: .bufferingOldest(2), count: 5)
    #expect(received == ["e1", "e2"])
  }

  @Test("bufferingNewest keeps the newest events instead, per policy")
  func bufferingNewestKeepsNewest() async throws {
    let received = try await drainAfterOvershoot(policy: .bufferingNewest(2), count: 5)
    #expect(received == ["e4", "e5"])
  }

  @Test("a consumer that keeps pace with a within-bound producer loses nothing")
  func withinBoundLosesNothing() async throws {
    let received = try await drainAfterOvershoot(policy: .bufferingOldest(64), count: 3)
    #expect(received == ["e1", "e2", "e3"])
  }

  @Test("the default buffer size matches Go's incomingChannelBuffer")
  func defaultBufferSizeMatchesGo() {
    #expect(EventStreamConfig.defaultBufferSize == 64)
    #expect(EventStreamConfig().bufferSize == 64)
  }
}
