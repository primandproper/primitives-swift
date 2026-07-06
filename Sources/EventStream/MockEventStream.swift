import Foundation

/// A recording ``EventStream`` test double: a test pushes events into it via ``emit(_:)`` / ``finish()``
/// and asserts on ``closeCallCount`` afterward. The receive-side analogue of the moq recorders used
/// elsewhere in the port (REPO-05: every seam ships a Noop and a Mock).
///
/// Where ``NoopEventStream`` never yields, this Mock lets a test *drive* the inbound sequence — the seam a
/// consumer of `any EventStream` is exercised against without a live SSE/WebSocket transport.
public actor MockEventStream: EventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  public private(set) var closeCallCount = 0
  private var closed = false

  public init() {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    self.events = AsyncThrowingStream { boundContinuation = $0 }
    self.continuation = boundContinuation
  }

  /// Pushes `event` to ``events``.
  public func emit(_ event: Event) {
    continuation.yield(event)
  }

  /// Finishes ``events``, optionally with a terminating error, without counting a ``close()`` call.
  public func finish(throwing error: (any Error)? = nil) {
    continuation.finish(throwing: error)
  }

  public func close() async {
    closeCallCount += 1
    guard !closed else { return }
    closed = true
    continuation.finish()
  }
}

/// A recording ``BidirectionalEventStream`` test double: like ``MockEventStream`` for the receive side,
/// plus it records every event the code-under-test ``send(_:)``s back to the server in ``sentEvents``.
public actor MockBidirectionalEventStream: BidirectionalEventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  public private(set) var closeCallCount = 0
  public private(set) var sentEvents: [Event] = []
  private var closed = false

  public init() {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    self.events = AsyncThrowingStream { boundContinuation = $0 }
    self.continuation = boundContinuation
  }

  /// Pushes `event` to ``events`` (the server-to-client direction).
  public func emit(_ event: Event) {
    continuation.yield(event)
  }

  /// Finishes ``events``, optionally with a terminating error, without counting a ``close()`` call.
  public func finish(throwing error: (any Error)? = nil) {
    continuation.finish(throwing: error)
  }

  public func send(_ event: Event) async throws {
    sentEvents.append(event)
  }

  public func close() async {
    closeCallCount += 1
    guard !closed else { return }
    closed = true
    continuation.finish()
  }
}
