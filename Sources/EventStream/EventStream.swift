/// A stream of inbound events, ported from platform-go's `eventstream.EventStream` — but flipped in
/// direction.
///
/// **Why the direction flips.** Go's `EventStream` models the *server's* end of a push connection: the
/// server calls `Send` to push an ``Event`` down the wire. This port targets the iOS *client* on the
/// other end of that same wire, so the client's `EventStream` is the receive side: it surfaces the
/// events the server pushes as ``events``, and closes the connection with ``close()``. The `Event` type
/// and the `Done`-channel-becomes-stream-termination shape both carry over unchanged; only who calls
/// `Send` differs.
///
/// ``close()`` is `async` (Go's `Close() error`) so an actor-backed conformer — ``SSEEventStream`` and
/// ``WebSocketEventStream`` both are — can tear down its background read loop without needing a
/// synchronous, cross-actor-isolation escape hatch.
public protocol EventStream: Sendable {
  /// Events pushed by the server. The sequence finishes when the connection ends (server close, network
  /// failure surfaced as a thrown error, or a local ``close()``) — the analogue of Go's `Done()` channel
  /// closing.
  var events: AsyncThrowingStream<Event, any Error> { get }

  /// Terminates the connection and finishes ``events``. Idempotent.
  func close() async
}

/// An ``EventStream`` that can also send events back to the server, ported from platform-go's
/// `eventstream.BidirectionalEventStream`.
///
/// Go adds `Receive()` to the server-side `EventStream` to read client-sent events. Flipped to the
/// client's perspective, the added capability is the client's own ``send(_:)`` — the events *it* pushes
/// to the server — while ``EventStream/events`` continues to carry what the server pushes down. Only
/// WebSocket supports this; SSE is receive-only by protocol design (see ``EventStreamError/bidirectionalUnsupported(provider:)``).
public protocol BidirectionalEventStream: EventStream {
  /// Sends `event` to the server.
  /// - Throws: ``EventStreamError/streamClosed`` if the stream has already been closed, or a transport
  ///   error from the underlying connection.
  func send(_ event: Event) async throws
}
