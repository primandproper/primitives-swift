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
  public var provider: EventStreamProvider
  public var webSocket: WebSocketEventStreamConfig?

  public init(provider: EventStreamProvider = .sse, webSocket: WebSocketEventStreamConfig? = nil) {
    self.provider = provider
    self.webSocket = webSocket
  }

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
  public func makeConnector(session: URLSession, observer: any Observer) -> any EventStreamConnector {
    switch provider {
    case .sse:
      return SSEEventStreamConnector(session: session, observer: observer)
    case .websocket:
      let connector = WebSocketEventStreamConnector(session: session, observer: observer)
      return AnyEventStreamConnector { url, headers in
        try await connector.connect(to: url, headers: headers)
      }
    }
  }

  /// Builds the bidirectional connector this config describes, mirroring Go's
  /// `config.ProvideBidirectionalEventStreamUpgrader`.
  /// - Throws: ``EventStreamError/bidirectionalUnsupported(provider:)`` for ``EventStreamProvider/sse``.
  public func makeBidirectionalConnector(
    session: URLSession, observer: any Observer
  ) throws -> any BidirectionalEventStreamConnector {
    switch provider {
    case .sse:
      throw EventStreamError.bidirectionalUnsupported(provider: .sse)
    case .websocket:
      return WebSocketEventStreamConnector(session: session, observer: observer)
    }
  }
}
