import Foundation

/// Connects to a server-pushed event stream, the client analogue of platform-go's
/// `eventstream.EventStreamUpgrader`.
///
/// Go's upgrader turns an inbound `http.Request` (already at the server) into an `EventStream` it can
/// push to. A client has no request to upgrade — it dials out — so this seam is "connect to a URL and
/// get a stream to read from" rather than "upgrade this request."
public protocol EventStreamConnector: Sendable {
  /// Connects to `url` and returns the resulting stream. Throws on any failure to establish the
  /// connection (transport failure, non-2xx response, etc).
  func connect(to url: URL) async throws -> any EventStream
}

/// Connects to a server-pushed, client-sendable event stream, the client analogue of platform-go's
/// `eventstream.BidirectionalEventStreamUpgrader`. Only ``WebSocketEventStreamConnector`` implements
/// this — SSE is receive-only by protocol design.
public protocol BidirectionalEventStreamConnector: Sendable {
  func connect(to url: URL) async throws -> any BidirectionalEventStream
}

/// Type-erases a closure into an ``EventStreamConnector``.
///
/// ``WebSocketEventStreamConnector`` only conforms to ``BidirectionalEventStreamConnector`` — its
/// `connect(to:)` returns `any BidirectionalEventStream` — so ``EventStreamConfig/makeConnector`` wraps
/// it in this to satisfy the plain (receive-only) ``EventStreamConnector`` interface for callers that
/// only need to read events regardless of provider. A `BidirectionalEventStream` already conforms to
/// `EventStream`, so this is a pure upcast, not a behavior change.
public struct AnyEventStreamConnector: EventStreamConnector {
  private let connectClosure: @Sendable (URL) async throws -> any EventStream

  public init(_ connect: @escaping @Sendable (URL) async throws -> any EventStream) {
    self.connectClosure = connect
  }

  public func connect(to url: URL) async throws -> any EventStream {
    try await connectClosure(url)
  }
}
