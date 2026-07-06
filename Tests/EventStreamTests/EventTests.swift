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

  @Test("a bare snowflake / high-precision-decimal payload round-trips byte-for-byte")
  func scalarLargeNumberPayloadsPreservePrecision() throws {
    // A `Double`-backed number would round `10000000000000000001` (an int64 past 2^53) to `1e+19` and
    // truncate the long decimal, silently corrupting the payload; the `Decimal` path preserves both.
    // These bare-number payloads have no object keys, so the round-trip is byte-for-byte deterministic.
    for literal in ["10000000000000000001", "3.141592653589793238462643383279"] {
      let event = Event(type: "minted", payload: Data(literal.utf8))
      let encoded = try JSONEncoder().encode(event)
      let decoded = try JSONDecoder().decode(Event.self, from: encoded)
      let decodedPayload = try #require(decoded.payload)
      #expect(String(decoding: decodedPayload, as: UTF8.self) == literal)
    }
  }

  @Test("a snowflake id and high-precision decimal survive an object-payload round-trip")
  func objectLargeNumberPayloadPreservesPrecision() throws {
    // Matches Go's `json.RawMessage` round-trip of the same input, produced by `json.Unmarshal`/
    // `json.Marshal` over `eventstream.Event` in platform-go (Go 1.26.4):
    //   in/out: {"type":"minted","payload":{"id":10000000000000000001,"ratio":3.14159265358979323846...}}
    // Object key order through a Swift `Dictionary` isn't deterministic, so assert the number literals
    // survive rather than the whole-object byte layout.
    let payloadJSON = #"{"id":10000000000000000001,"ratio":3.141592653589793238462643383279}"#
    let event = Event(type: "minted", payload: Data(payloadJSON.utf8))

    let encoded = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(Event.self, from: encoded)

    let roundTripped = String(decoding: try #require(decoded.payload), as: UTF8.self)
    #expect(roundTripped.contains("10000000000000000001"))
    #expect(roundTripped.contains("3.141592653589793238462643383279"))
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
