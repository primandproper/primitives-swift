import Foundation
import Testing

@testable import Capitalism

@Suite("RevenueCatConfig")
struct RevenueCatConfigTests {
  @Test("a non-empty API key validates")
  func standard() throws {
    try RevenueCatConfig(apiKey: "appl_xxx").validate()
  }

  @Test("an empty API key fails validation")
  func emptyAPIKey() {
    #expect(throws: RevenueCatConfigError.missingAPIKey) {
      try RevenueCatConfig().validate()
    }
  }

  @Test("decodes the JSON shape (\"apiKey\" key)")
  func decodesShape() throws {
    let config = try JSONDecoder().decode(
      RevenueCatConfig.self, from: Data(#"{"apiKey":"appl_xxx"}"#.utf8))
    #expect(config.apiKey == "appl_xxx")
  }

  @Test("a missing apiKey decodes to the empty string")
  func missingKey() throws {
    let config = try JSONDecoder().decode(RevenueCatConfig.self, from: Data("{}".utf8))
    #expect(config.apiKey.isEmpty)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = RevenueCatConfig(apiKey: "appl_xxx")
    let decoded = try JSONDecoder().decode(
      RevenueCatConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
