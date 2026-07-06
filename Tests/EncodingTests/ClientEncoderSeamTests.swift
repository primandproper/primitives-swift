import Foundation
import Testing

@testable import Encoding

private struct Payload: Codable, Equatable {
  var name: String
  var count: Int
}

@Suite("ClientEncoder seam doubles")
struct ClientEncoderSeamTests {
  @Test("NoopClientEncoder encodes to nothing and refuses to decode")
  func noopIsInert() throws {
    let noop = NoopClientEncoder()
    #expect(noop.contentType == .json)
    #expect(try noop.encode(Payload(name: "a", count: 1)).isEmpty)
    #expect(throws: EncoderError.codecDisabled) {
      _ = try noop.decode(Payload.self, from: Data("{}".utf8))
    }
  }

  @Test("MockClientEncoder round-trips via its backing codec and records calls")
  func mockRecordsAndRoundTrips() throws {
    let mock = MockClientEncoder()
    let value = Payload(name: "b", count: 2)

    let data = try mock.encode(value)
    let back = try mock.decode(Payload.self, from: data)

    #expect(back == value)
    #expect(mock.encodeCount == 1)
    #expect(mock.decodeCount == 1)
    #expect(mock.encodedPayloads == [data])
    #expect(mock.decodedInputs == [data])
  }

  @Test("MockClientEncoder gate closures drive the caller's error paths")
  func mockGatesThrow() {
    struct Boom: Error {}
    let onEncode = MockClientEncoder(onEncode: { throw Boom() })
    #expect(throws: Boom.self) { _ = try onEncode.encode(Payload(name: "c", count: 3)) }
    #expect(onEncode.encodeCount == 1)
    #expect(onEncode.encodedPayloads.isEmpty)

    let onDecode = MockClientEncoder(onDecode: { throw Boom() })
    #expect(throws: Boom.self) { _ = try onDecode.decode(Payload.self, from: Data("{}".utf8)) }
    #expect(onDecode.decodeCount == 1)
  }
}
