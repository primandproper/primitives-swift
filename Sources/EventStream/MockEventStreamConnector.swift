import Foundation

/// A recording ``EventStreamConnector`` test double: it captures every ``connect(to:headers:)`` call —
/// URL and headers — in ``connectCalls`` and hands back a stream from an injectable factory (defaulting
/// to a fresh ``NoopEventStream``). The Mock counterpart to ``NoopEventStreamConnector`` under REPO-05.
///
/// Recording the headers is the point: it's how a test asserts a caller propagated `Authorization` or a
/// reconnect's `Last-Event-ID` without a live server.
public actor MockEventStreamConnector: EventStreamConnector {
  /// A recorded ``connect(to:headers:)`` invocation.
  public struct ConnectCall: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
  }

  public private(set) var connectCalls: [ConnectCall] = []
  private let streamFactory: @Sendable () -> any EventStream

  /// - Parameter stream: produces the stream each ``connect(to:headers:)`` returns. Defaults to a fresh
  ///   ``NoopEventStream`` so the connector is usable with no configuration.
  public init(stream: @escaping @Sendable () -> any EventStream = { NoopEventStream() }) {
    self.streamFactory = stream
  }

  public func connect(to url: URL, headers: [String: String]) async throws -> any EventStream {
    connectCalls.append(ConnectCall(url: url, headers: headers))
    return streamFactory()
  }
}

/// A recording ``BidirectionalEventStreamConnector`` test double, the bidirectional analogue of
/// ``MockEventStreamConnector``; its factory defaults to a fresh ``NoopBidirectionalEventStream``.
public actor MockBidirectionalEventStreamConnector: BidirectionalEventStreamConnector {
  /// A recorded ``connect(to:headers:)`` invocation.
  public struct ConnectCall: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
  }

  public private(set) var connectCalls: [ConnectCall] = []
  private let streamFactory: @Sendable () -> any BidirectionalEventStream

  public init(
    stream: @escaping @Sendable () -> any BidirectionalEventStream = {
      NoopBidirectionalEventStream()
    }
  ) {
    self.streamFactory = stream
  }

  public func connect(
    to url: URL, headers: [String: String]
  ) async throws -> any BidirectionalEventStream {
    connectCalls.append(ConnectCall(url: url, headers: headers))
    return streamFactory()
  }
}
