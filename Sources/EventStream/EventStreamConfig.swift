import Foundation
import Observability

/// The event stream transport, ported from platform-go's `config.ProviderSSE`/`config.ProviderWebSocket`
/// string constants.
///
/// Go models `Config.Provider` as a bare, ozzo-`validation.In`-checked string. This is the same move
/// ``Encoding``'s `ContentType` and ``Cryptography``'s `EncryptionProvider` make: a closed, self-
/// validating enum whose raw value **is** the wire string, so a Go-authored `{"provider":"sse"}` decodes
/// directly and an unrecognized value fails at decode time instead of needing a separate validation pass.
public enum EventStreamProvider: String, Codable, Sendable, CaseIterable {
  case sse
  case websocket
}

/// Configuration selecting and building an event stream connector, ported from platform-go's
/// `eventstream/config.Config`.
///
/// Only the JSON contract survives the port (see ``WebSocketEventStreamConfig`` for the field-by-field
/// reasoning); this struct's own wire keys — `provider` and `websocket` — match Go's exactly.
public struct EventStreamConfig: Codable, Sendable, Equatable {
  /// The number of events a connected stream buffers before a non-draining consumer starts dropping the
  /// overflow — Go's `incomingChannelBuffer` (`eventstream/websocket/websocket.go`), the bound its
  /// WebSocket `incoming` channel is `make`d with. Go hardwires this constant rather than exposing it as
  /// config, so it has no JSON wire key here; it's a Swift-side tunable defaulting to Go's value.
  public static let defaultBufferSize = 64

  public var provider: EventStreamProvider
  public var webSocket: WebSocketEventStreamConfig?

  /// Slots a connected SSE/WebSocket stream buffers before a slow consumer's overflow is dropped
  /// (`.bufferingOldest`). Not part of the Go JSON contract — see ``defaultBufferSize`` — so it is
  /// neither encoded nor decoded; a Go-authored config blob round-trips unchanged and leaves this at 64.
  public var bufferSize: Int = EventStreamConfig.defaultBufferSize

  public init(
    provider: EventStreamProvider = .sse,
    webSocket: WebSocketEventStreamConfig? = nil,
    bufferSize: Int = EventStreamConfig.defaultBufferSize
  ) {
    self.provider = provider
    self.webSocket = webSocket
    self.bufferSize = bufferSize
  }

  // `bufferSize` is intentionally omitted: it isn't a Go wire field, so keeping it out of CodingKeys
  // (it falls back to its default on decode and is never encoded) preserves byte-for-byte JSON compat.
  private enum CodingKeys: String, CodingKey {
    case provider
    case webSocket = "websocket"
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`: a `.websocket` provider requires
  /// ``webSocket`` to be present. (`provider` itself needs no membership check here — decoding a Config
  /// already fails for a provider string outside ``EventStreamProvider``'s cases.)
  public func validate() throws {
    if provider == .websocket, webSocket == nil {
      throw EventStreamError.invalidConfig("websocket provider requires websocket config")
    }
  }

  /// Builds the receive-only connector this config describes, mirroring Go's
  /// `config.ProvideEventStreamUpgrader`. Every provider supports this (SSE included).
  ///
  /// When `session` is `nil` the connector is built over ``StreamingSession/make()``, a session with
  /// streaming-safe timeouts (see ``StreamingSession``); pass a session to inject your own. Callers that
  /// hand in `URLSessionConfiguration.default` would otherwise have quiet/long streams killed by its
  /// finite resource and inter-byte idle timeouts.
  public func makeConnector(
    session: URLSession? = nil, observer: any Observer
  ) -> any EventStreamConnector {
    let session = session ?? StreamingSession.make()
    switch provider {
    case .sse:
      return SSEEventStreamConnector(
        session: session, observer: observer, bufferSize: bufferSize)
    case .websocket:
      let connector = WebSocketEventStreamConnector(
        session: session, observer: observer, bufferSize: bufferSize,
        config: webSocket ?? WebSocketEventStreamConfig())
      return AnyEventStreamConnector { url, headers in
        try await connector.connect(to: url, headers: headers)
      }
    }
  }

  /// Builds the bidirectional connector this config describes, mirroring Go's
  /// `config.ProvideBidirectionalEventStreamUpgrader`.
  ///
  /// As with ``makeConnector(session:observer:)``, a `nil` session defaults to ``StreamingSession/make()``.
  /// - Throws: ``EventStreamError/bidirectionalUnsupported(provider:)`` for ``EventStreamProvider/sse``.
  public func makeBidirectionalConnector(
    session: URLSession? = nil, observer: any Observer
  ) throws -> any BidirectionalEventStreamConnector {
    switch provider {
    case .sse:
      throw EventStreamError.bidirectionalUnsupported(provider: .sse)
    case .websocket:
      let session = session ?? StreamingSession.make()
      return WebSocketEventStreamConnector(
        session: session, observer: observer, bufferSize: bufferSize,
        config: webSocket ?? WebSocketEventStreamConfig())
    }
  }
}
