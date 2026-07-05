import Foundation
import Testing

@testable import Analytics

@Suite("SegmentConfig")
struct SegmentConfigTests {
  @Test("a non-empty API token validates")
  func standard() throws {
    try SegmentConfig(apiToken: "token").validate()
  }

  @Test("an empty API token fails validation")
  func emptyAPIToken() {
    #expect(throws: SegmentConfigError.missingAPIToken) {
      try SegmentConfig().validate()
    }
  }

  @Test("decodes the Go JSON shape (\"apiToken\" key)")
  func decodesGoShape() throws {
    let config = try JSONDecoder().decode(SegmentConfig.self, from: Data(#"{"apiToken":"tok"}"#.utf8))
    #expect(config.apiToken == "tok")
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = SegmentConfig(apiToken: "tok")
    let decoded = try JSONDecoder().decode(
      SegmentConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
