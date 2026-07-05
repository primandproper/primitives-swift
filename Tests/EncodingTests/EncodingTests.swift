import Foundation
import Testing

@testable import Encoding

/// A small Codable payload standing in for the Go tests' `example{Name string}`.
private struct Example: Codable, Equatable {
  var name: String
}

@Suite("ContentType negotiation")
struct ContentTypeTests {
  @Test("raw values / header values mirror the Go MIME constants")
  func rawValues() {
    #expect(ContentType.json.rawValue == "application/json")
    #expect(ContentType.xml.rawValue == "application/xml")
    #expect(ContentType.toml.rawValue == "application/toml")
    #expect(ContentType.yaml.rawValue == "application/yaml")
    #expect(ContentType.emoji.rawValue == "application/emoji")
    #expect(ContentType.json.headerValue == "application/json")
  }

  @Test("from(header:) resolves each canonical MIME string", arguments: ContentType.allCases)
  func fromHeaderCanonical(contentType: ContentType) {
    #expect(ContentType.from(header: contentType.rawValue) == contentType)
  }

  @Test("from(header:) strips a charset parameter")
  func fromHeaderIgnoresCharset() {
    #expect(ContentType.from(header: "application/json; charset=utf-8") == .json)
    #expect(ContentType.from(header: "application/xml; charset=utf-8") == .xml)
  }

  @Test("from(header:) trims and lowercases before matching")
  func fromHeaderNormalizes() {
    #expect(ContentType.from(header: "  APPLICATION/JSON  ") == .json)
  }

  @Test("from(header:) falls back to JSON for unknown or empty values")
  func fromHeaderDefaults() {
    #expect(ContentType.from(header: "unknown") == .json)
    #expect(ContentType.from(header: "") == .json)
  }

  @Test("Codable is strict: a canonical string round-trips, junk fails to decode")
  func codableStrict() throws {
    // Wrapped in an object so the assertion never depends on top-level JSON-fragment support.
    struct Holder: Codable, Equatable { var ct: ContentType }

    let encoded = try JSONEncoder().encode(Holder(ct: .xml))
    // Foundation's JSONEncoder escapes forward slashes as `\/` (valid JSON; Go decodes it fine).
    #expect(String(decoding: encoded, as: UTF8.self) == #"{"ct":"application\/xml"}"#)

    let decoded = try JSONDecoder().decode(Holder.self, from: encoded)
    #expect(decoded.ct == .xml)

    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(Holder.self, from: Data(#"{"ct":"nope"}"#.utf8))
    }
  }
}

@Suite("ClientEncoder factory")
struct ClientEncoderFactoryTests {
  @Test("JSON builds a working encoder")
  func jsonSupported() throws {
    let encoder = try ContentType.json.makeClientEncoder()
    #expect(encoder.contentType == .json)
  }

  @Test(
    "unsupported content types throw",
    arguments: [ContentType.xml, .toml, .yaml, .emoji])
  func unsupportedThrows(contentType: ContentType) {
    #expect(throws: EncoderError.unsupportedContentType(contentType)) {
      _ = try contentType.makeClientEncoder()
    }
  }
}

@Suite("JSONClientEncoder round-trip")
struct JSONClientEncoderTests {
  @Test("encodes and decodes a value symmetrically")
  func roundTrip() throws {
    let encoder = JSONClientEncoder()
    let original = Example(name: "name")

    let data = try encoder.encode(original)
    let decoded = try encoder.decode(Example.self, from: data)

    #expect(decoded == original)
  }

  @Test("decodes the Go JSON wire shape")
  func decodesGoShape() throws {
    let encoder = JSONClientEncoder()
    let decoded = try encoder.decode(Example.self, from: Data(#"{"name":"name"}"#.utf8))
    #expect(decoded == Example(name: "name"))
  }

  @Test("propagates a decode failure on malformed input")
  func decodeFailure() {
    let encoder = JSONClientEncoder()
    #expect(throws: (any Error).self) {
      _ = try encoder.decode(Example.self, from: Data(#"{"name"   "#.utf8))
    }
  }

  @Test("honors an injected encoder configuration")
  func configuredEncoder() throws {
    let encoder = JSONClientEncoder(configureEncoder: { $0.outputFormatting = [.sortedKeys] })
    let data = try encoder.encode(Example(name: "name"))
    #expect(String(decoding: data, as: UTF8.self) == #"{"name":"name"}"#)
  }
}

@Suite("EncodingConfig")
struct EncodingConfigTests {
  @Test("decodes the Go JSON shape (\"contentType\" key)")
  func decodesGoShape() throws {
    let config = try JSONDecoder().decode(
      EncodingConfig.self, from: Data(#"{"contentType":"application/json"}"#.utf8))
    #expect(config.contentType == "application/json")
    #expect(config.resolvedContentType == .json)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = EncodingConfig(contentType: "application/xml")
    let decoded = try JSONDecoder().decode(
      EncodingConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }

  @Test("resolves an unknown content type to JSON (matching Go's lenient provider)")
  func resolvesUnknownToJSON() {
    #expect(EncodingConfig(contentType: "garbage").resolvedContentType == .json)
    #expect(EncodingConfig(contentType: "").resolvedContentType == .json)
  }

  @Test("builds a JSON client encoder from a JSON config")
  func makesJSONEncoder() throws {
    let encoder = try EncodingConfig(contentType: "application/json").makeClientEncoder()
    #expect(encoder.contentType == .json)
  }

  @Test("propagates the unsupported-content-type error for a non-JSON config")
  func makesUnsupportedThrows() {
    #expect(throws: EncoderError.unsupportedContentType(.yaml)) {
      _ = try EncodingConfig(contentType: "application/yaml").makeClientEncoder()
    }
  }
}

@Suite("EncoderError messages")
struct EncoderErrorTests {
  @Test("message names the offending content type")
  func message() {
    #expect(
      EncoderError.unsupportedContentType(.xml).errorDescription
        == "unsupported content type: application/xml")
  }
}
