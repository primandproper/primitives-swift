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
  ///
  /// `headers` are set on the outbound request (e.g. `Authorization`), letting callers carry auth
  /// without smuggling secrets through query params. This is also the seam a later reconnecting
  /// wrapper (NET-20) uses to add a `Last-Event-ID` header on resume — it needs no further API.
  func connect(to url: URL, headers: [String: String]) async throws -> any EventStream
}

extension EventStreamConnector {
  /// Source-compatible convenience for callers that pass no custom headers.
  public func connect(to url: URL) async throws -> any EventStream {
    try await connect(to: url, headers: [:])
  }
}

/// Connects to a server-pushed, client-sendable event stream, the client analogue of platform-go's
/// `eventstream.BidirectionalEventStreamUpgrader`. Only ``WebSocketEventStreamConnector`` implements
/// this — SSE is receive-only by protocol design.
public protocol BidirectionalEventStreamConnector: Sendable {
  /// See ``EventStreamConnector/connect(to:headers:)`` for the `headers` contract.
  func connect(to url: URL, headers: [String: String]) async throws -> any BidirectionalEventStream
}

extension BidirectionalEventStreamConnector {
  /// Source-compatible convenience for callers that pass no custom headers.
  public func connect(to url: URL) async throws -> any BidirectionalEventStream {
    try await connect(to: url, headers: [:])
  }
}

/// Type-erases a closure into an ``EventStreamConnector``.
///
/// ``WebSocketEventStreamConnector`` only conforms to ``BidirectionalEventStreamConnector`` — its
/// `connect(to:)` returns `any BidirectionalEventStream` — so ``EventStreamConfig/makeConnector`` wraps
/// it in this to satisfy the plain (receive-only) ``EventStreamConnector`` interface for callers that
/// only need to read events regardless of provider. A `BidirectionalEventStream` already conforms to
/// `EventStream`, so this is a pure upcast, not a behavior change.
public struct AnyEventStreamConnector: EventStreamConnector {
  private let connectClosure: @Sendable (URL, [String: String]) async throws -> any EventStream

  public init(
    _ connect: @escaping @Sendable (URL, [String: String]) async throws -> any EventStream
  ) {
    self.connectClosure = connect
  }

  public func connect(to url: URL, headers: [String: String] = [:]) async throws -> any EventStream
  {
    try await connectClosure(url, headers)
  }
}
