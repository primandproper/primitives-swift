import Foundation

/// The shared factory for the bounded `AsyncThrowingStream<Event, any Error>` that both
/// ``SSEEventStream`` and ``WebSocketEventStream`` yield their decoded events into.
///
/// Both streams pump events from a background read loop into a continuation a consumer drains at its
/// own pace. Left unbounded, a slow (or stalled) consumer lets that buffer grow without limit — the
/// exact unbounded-memory hazard platform-go avoids by bounding its WebSocket `incoming` channel at
/// `incomingChannelBuffer = 64` (`eventstream/websocket/websocket.go`). Routing both streams' buffer
/// construction through this one seam guarantees neither can be created unbounded by accident, and gives
/// the buffering policy a single testable point.
///
/// A buffered channel in Go blocks its sender once full (backpressure); an `AsyncThrowingStream` has no
/// blocking-yield equivalent, so the nearest bound is a `BufferingPolicy` that caps occupancy and drops
/// the overflow. The default is ``EventStreamConfig/defaultBufferSize`` slots of `.bufferingOldest`, so
/// the cap and drop-direction are explicit at every call site rather than relying on the "unbounded"
/// default of `AsyncThrowingStream.init`.
enum BoundedEventStream {
  static func make(
    bufferingPolicy: AsyncThrowingStream<Event, any Error>.Continuation.BufferingPolicy
  ) -> (
    stream: AsyncThrowingStream<Event, any Error>,
    continuation: AsyncThrowingStream<Event, any Error>.Continuation
  ) {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    let stream = AsyncThrowingStream(bufferingPolicy: bufferingPolicy) { boundContinuation = $0 }
    return (stream, boundContinuation)
  }
}
