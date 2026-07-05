import Foundation

/// A no-op ``EventStream``, ported from platform-go's `eventstream/noop.EventStream`.
///
/// Never yields an event; ``events`` only finishes once ``close()`` is called, mirroring Go's `Done()`
/// channel, which stays open until `Close`.
public actor NoopEventStream: EventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  private var closed = false

  public init() {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    self.events = AsyncThrowingStream { boundContinuation = $0 }
    self.continuation = boundContinuation
  }

  public func close() async {
    guard !closed else { return }
    closed = true
    continuation.finish()
  }
}

/// A no-op ``BidirectionalEventStream``, ported from platform-go's
/// `eventstream/noop.BidirectionalEventStream`. ``send(_:)`` is a no-op that never throws, mirroring
/// Go's `Send` returning `nil` unconditionally.
public actor NoopBidirectionalEventStream: BidirectionalEventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  private var closed = false

  public init() {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    self.events = AsyncThrowingStream { boundContinuation = $0 }
    self.continuation = boundContinuation
  }

  public func send(_ event: Event) async throws {}

  public func close() async {
    guard !closed else { return }
    closed = true
    continuation.finish()
  }
}

/// A no-op ``EventStreamConnector``, ported from platform-go's `eventstream/noop.EventStreamUpgrader`.
public struct NoopEventStreamConnector: EventStreamConnector {
  public init() {}

  public func connect(to url: URL) async throws -> any EventStream {
    NoopEventStream()
  }
}

/// A no-op ``BidirectionalEventStreamConnector``, ported from platform-go's
/// `eventstream/noop.BidirectionalEventStreamUpgrader`.
public struct NoopBidirectionalEventStreamConnector: BidirectionalEventStreamConnector {
  public init() {}

  public func connect(to url: URL) async throws -> any BidirectionalEventStream {
    NoopBidirectionalEventStream()
  }
}
