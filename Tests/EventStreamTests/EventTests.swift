import Foundation
import Testing

@testable import EventStream

@Suite("Event Codable")
struct EventCodableTests {
  @Test("a JSON object payload round-trips as embedded structure, not base64")
  func objectPayloadRoundTrips() throws {
    let event = Event(type: "update", payload: Data(#"{"id":"abc","status":"done"}"#.utf8))

    let data = try JSONEncoder().encode(event)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["type"] as? String == "update")
    let payload = try #require(json["payload"] as? [String: Any])
    #expect(payload["id"] as? String == "abc")
    #expect(payload["status"] as? String == "done")

    let decoded = try JSONDecoder().decode(Event.self, from: data)
    #expect(decoded.type == "update")
    let decodedPayloadData = try #require(decoded.payload)
    let decodedPayload = try #require(
      try JSONSerialization.jsonObject(with: decodedPayloadData) as? [String: Any])
    #expect(decodedPayload["id"] as? String == "abc")
  }

  @Test("an array payload round-trips")
  func arrayPayloadRoundTrips() throws {
    let event = Event(type: "batch", payload: Data("[1,2,3]".utf8))

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(Event.self, from: data)

    let payloadData = try #require(decoded.payload)
    let array = try #require(try JSONSerialization.jsonObject(with: payloadData) as? [Any])
    #expect(array.count == 3)
  }

  @Test("a nil payload omits the payload key, matching Go's `json:\"payload,omitempty\"`")
  func nilPayloadOmitsKey() throws {
    let event = Event(type: "ping")

    let data = try JSONEncoder().encode(event)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["type"] as? String == "ping")
    #expect(json["payload"] == nil)
  }

  @Test("decoding a payload-less JSON object yields a nil payload")
  func decodingWithoutPayloadYieldsNil() throws {
    let data = Data(#"{"type":"ping"}"#.utf8)
    let decoded = try JSONDecoder().decode(Event.self, from: data)

    #expect(decoded.type == "ping")
    #expect(decoded.payload == nil)
  }

  @Test("a scalar payload (string/number/bool/null) round-trips")
  func scalarPayloadsRoundTrip() throws {
    for (json, expectedType) in [
      (#"{"type":"s","payload":"hello"}"#, "s"),
      (#"{"type":"n","payload":42}"#, "n"),
      (#"{"type":"b","payload":true}"#, "b"),
      (#"{"type":"z","payload":null}"#, "z"),
    ] {
      let decoded = try JSONDecoder().decode(Event.self, from: Data(json.utf8))
      #expect(decoded.type == expectedType)

      let reencoded = try JSONEncoder().encode(decoded)
      let redecoded = try JSONDecoder().decode(Event.self, from: reencoded)
      #expect(redecoded.type == expectedType)
    }
  }
}
