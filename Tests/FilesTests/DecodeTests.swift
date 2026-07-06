import Encoding
import Foundation
import Testing

@testable import Files

private struct Sample: Codable, Equatable {
  var name: String
  var count: Int
}

@Suite("decode / decodeFile")
struct DecodeTests {
  @Test("decode round-trips a Codable value through the Encoding module")
  func roundTrip() throws {
    let data = Data(#"{"name":"platform","count":2}"#.utf8)
    let got = try decode(Sample.self, from: data, contentType: .json)
    #expect(got == Sample(name: "platform", count: 2))
  }

  @Test("decodeFile reads and decodes a file's contents")
  func decodeFileRoundTrip() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path
    try #"{"name":"platform","count":2}"#.write(toFile: path, atomically: true, encoding: .utf8)

    let got = try decodeFile(Sample.self, atPath: path, contentType: .json)
    #expect(got == Sample(name: "platform", count: 2))
  }

  @Test("empty input throws emptyInput")
  func emptyInput() throws {
    #expect(throws: FilesError.emptyInput) {
      _ = try decode(Sample.self, from: Data(), contentType: .json)
    }
  }

  @Test("an unsupported content type throws before attempting to decode")
  func unsupportedContentType() throws {
    let data = Data(#"{"name":"platform","count":2}"#.utf8)
    #expect(throws: EncoderError.unsupportedContentType(.yaml)) {
      _ = try decode(Sample.self, from: data, contentType: .yaml)
    }
  }

  @Test("decodeFile surfaces a missing-file error")
  func decodeFileMissing() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).path

    #expect(throws: (any Error).self) {
      _ = try decodeFile(Sample.self, atPath: path, contentType: .json)
    }
  }
}
