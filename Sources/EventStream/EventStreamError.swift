/// Errors surfaced by this module, ported from the failure modes of platform-go's `eventstream`
/// packages (the SSE/WebSocket upgraders' error strings and the config factory's `errors.Newf`).
public enum EventStreamError: Error, Equatable, Sendable, CustomStringConvertible {
  /// Connecting succeeded at the transport level but the server returned a non-2xx status, so there is
  /// no stream to hand back. Go's server-side upgraders have no equivalent (they never dial out); this
  /// is specific to being the client end of the connection.
  case connectionFailed(status: Int)
  /// The response wasn't an `HTTPURLResponse` (e.g. a non-HTTP URL scheme), so there is no status code
  /// to reason about.
  case nonHTTPResponse
  /// A send or close was attempted on a stream that already terminated. Mirrors the "stream closed"
  /// error both `sse.sseStream.Send` and `websocket.wsStream.Send` return after `Close`.
  case streamClosed
  /// The config failed validation. Carries the human-readable reason.
  case invalidConfig(String)
  /// The provider doesn't support a bidirectional stream, mirroring
  /// `config.ProvideBidirectionalEventStreamUpgrader`'s "SSE does not support bidirectional event
  /// streams" error. SSE is the only such provider today.
  case bidirectionalUnsupported(provider: EventStreamProvider)
  /// A 2xx SSE response arrived with a `Content-Type` that isn't `text/event-stream` (e.g. an HTML error
  /// page served with a 200). Per the [SSE spec](https://html.spec.whatwg.org/multipage/server-sent-events.html#sse-processing-model),
  /// the client must verify the MIME type and fail the connection otherwise, rather than parse the body
  /// as an event stream and silently observe nothing. Carries the received value (`nil` if absent).
  case invalidContentType(received: String?)
  /// A WebSocket heartbeat ping was sent but no pong arrived within the timeout window, so the connection
  /// is treated as dead. Mirrors the intent of Go's server-side `heartbeatInterval` liveness check.
  case pongTimeout

  public var description: String {
    switch self {
    case .connectionFailed(let status):
      return "event stream connection failed with status \(status)"
    case .nonHTTPResponse:
      return "response was not an HTTP response"
    case .streamClosed:
      return "stream closed"
    case .invalidConfig(let reason):
      return "invalid event stream config: \(reason)"
    case .bidirectionalUnsupported(let provider):
      return "\(provider.rawValue) does not support bidirectional event streams"
    case .invalidContentType(let received):
      return "expected Content-Type text/event-stream, got \(received ?? "none")"
    case .pongTimeout:
      return "websocket pong not received within the heartbeat interval"
    }
  }
}
