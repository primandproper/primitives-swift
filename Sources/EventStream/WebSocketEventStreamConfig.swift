import Foundation

/// WebSocket-specific configuration, ported from platform-go's `websocket.Config`.
///
/// Every field here is server-upgrader configuration in Go: ``allowedOrigins`` drives
/// `gorilla/websocket`'s `CheckOrigin` (who may *connect to* the server), and ``readBufferSize``/
/// ``writeBufferSize`` size the server's accept-side socket buffers. A client dialing out has no
/// `CheckOrigin` decision to make and `URLSessionWebSocketTask` exposes no buffer-size knobs at all —
/// the same "no `URLSession` analogue, kept for wire-compat" situation `HTTPClientConfig.maxIdleConns`
/// documents. ``heartbeatInterval`` is carried the same way: Go's server actively pings on this
/// interval to detect dead clients, but `URLSessionWebSocketTask` answers a peer's ping with a pong
/// automatically at the transport level (no app-level ping loop needed), so there is nothing for a
/// client-side timer to drive. All four fields exist purely so a Go-authored config JSON blob still
/// decodes; none of them change ``WebSocketEventStreamConnector``'s behavior.
public struct WebSocketEventStreamConfig: Codable, Sendable, Equatable {
  public var allowedOrigins: [String]
  public var heartbeatInterval: Duration
  public var readBufferSize: Int
  public var writeBufferSize: Int

  public init(
    allowedOrigins: [String] = [],
    heartbeatInterval: Duration = .zero,
    readBufferSize: Int = 0,
    writeBufferSize: Int = 0
  ) {
    self.allowedOrigins = allowedOrigins
    self.heartbeatInterval = heartbeatInterval
    self.readBufferSize = readBufferSize
    self.writeBufferSize = writeBufferSize
  }

  private enum CodingKeys: String, CodingKey {
    case allowedOrigins
    case heartbeatInterval
    case readBufferSize
    case writeBufferSize
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    allowedOrigins = try container.decodeIfPresent([String].self, forKey: .allowedOrigins) ?? []
    heartbeatInterval = .nanoseconds(
      try container.decodeIfPresent(Int64.self, forKey: .heartbeatInterval) ?? 0)
    readBufferSize = try container.decodeIfPresent(Int.self, forKey: .readBufferSize) ?? 0
    writeBufferSize = try container.decodeIfPresent(Int.self, forKey: .writeBufferSize) ?? 0
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(allowedOrigins, forKey: .allowedOrigins)
    try container.encode(heartbeatInterval.wholeNanoseconds, forKey: .heartbeatInterval)
    try container.encode(readBufferSize, forKey: .readBufferSize)
    try container.encode(writeBufferSize, forKey: .writeBufferSize)
  }
}

extension Duration {
  /// This duration as a whole count of nanoseconds, the unit Go's `time.Duration` marshals to JSON as.
  /// `HTTPClientConfig`/`RetryConfig` each carry an identical private copy rather than reaching across a
  /// target boundary for a two-line conversion; this module does the same.
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
  }
}
