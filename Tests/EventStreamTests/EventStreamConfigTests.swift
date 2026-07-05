import Foundation
import Observability
import Testing

@testable import EventStream

@Suite("EventStreamConfig")
struct EventStreamConfigTests {
  @Test("SSE provider validates without a websocket config")
  func sseValidates() throws {
    let cfg = EventStreamConfig(provider: .sse)
    try cfg.validate()
  }

  @Test("websocket provider requires a websocket config")
  func websocketRequiresConfig() {
    let cfg = EventStreamConfig(provider: .websocket)
    #expect(throws: EventStreamError.self) { try cfg.validate() }
  }

  @Test("websocket provider validates once a websocket config is present")
  func websocketValidatesWithConfig() throws {
    let cfg = EventStreamConfig(provider: .websocket, webSocket: WebSocketEventStreamConfig())
    try cfg.validate()
  }

  @Test("makeConnector returns an SSE connector for the SSE provider")
  func makeConnectorSSE() {
    let cfg = EventStreamConfig(provider: .sse)
    let connector = cfg.makeConnector(session: .shared, observer: recordingObserver("test"))
    #expect(connector is SSEEventStreamConnector)
  }

  @Test("makeConnector returns an erased websocket connector for the websocket provider")
  func makeConnectorWebSocket() {
    let cfg = EventStreamConfig(provider: .websocket, webSocket: WebSocketEventStreamConfig())
    let connector = cfg.makeConnector(session: .shared, observer: recordingObserver("test"))
    #expect(connector is AnyEventStreamConnector)
  }

  @Test("makeBidirectionalConnector throws for SSE")
  func makeBidirectionalConnectorSSEThrows() {
    let cfg = EventStreamConfig(provider: .sse)
    #expect(throws: EventStreamError.bidirectionalUnsupported(provider: .sse)) {
      try cfg.makeBidirectionalConnector(session: .shared, observer: recordingObserver("test"))
    }
  }

  @Test("makeBidirectionalConnector returns a websocket connector for the websocket provider")
  func makeBidirectionalConnectorWebSocket() throws {
    let cfg = EventStreamConfig(provider: .websocket, webSocket: WebSocketEventStreamConfig())
    let connector = try cfg.makeBidirectionalConnector(
      session: .shared, observer: recordingObserver("test"))
    #expect(connector is WebSocketEventStreamConnector)
  }

  @Test("wire keys and provider strings match Go's config.Config")
  func wireKeysMatchGo() throws {
    let cfg = EventStreamConfig(
      provider: .websocket,
      webSocket: WebSocketEventStreamConfig(
        allowedOrigins: ["https://example.com"], heartbeatInterval: .seconds(30),
        readBufferSize: 1024, writeBufferSize: 2048))

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["provider"] as? String == "websocket")
    let ws = try #require(json["websocket"] as? [String: Any])
    #expect(ws["allowedOrigins"] as? [String] == ["https://example.com"])
    #expect((ws["heartbeatInterval"] as? NSNumber)?.int64Value == 30_000_000_000)
    #expect(ws["readBufferSize"] as? Int == 1024)
    #expect(ws["writeBufferSize"] as? Int == 2048)

    let decoded = try JSONDecoder().decode(EventStreamConfig.self, from: data)
    #expect(decoded == cfg)
  }

  @Test("an unrecognized provider string fails to decode")
  func unrecognizedProviderFailsDecode() {
    let data = Data(#"{"provider":"carrier-pigeon"}"#.utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(EventStreamConfig.self, from: data) }
  }
}

@Suite("WebSocketEventStreamConfig Codable")
struct WebSocketEventStreamConfigCodableTests {
  @Test("heartbeatInterval encodes as integer nanoseconds, matching Go's time.Duration")
  func heartbeatEncodesNanoseconds() throws {
    let cfg = WebSocketEventStreamConfig(heartbeatInterval: .seconds(15))

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect((json["heartbeatInterval"] as? NSNumber)?.int64Value == 15_000_000_000)

    let decoded = try JSONDecoder().decode(WebSocketEventStreamConfig.self, from: data)
    #expect(decoded == cfg)
  }

  @Test("a partial JSON object decodes missing fields to zero values")
  func partialJSONDecodesToZero() throws {
    let data = Data(#"{"heartbeatInterval": 5000000000}"#.utf8)
    let decoded = try JSONDecoder().decode(WebSocketEventStreamConfig.self, from: data)

    #expect(decoded.heartbeatInterval == .seconds(5))
    #expect(decoded.allowedOrigins.isEmpty)
    #expect(decoded.readBufferSize == 0)
    #expect(decoded.writeBufferSize == 0)
  }
}
