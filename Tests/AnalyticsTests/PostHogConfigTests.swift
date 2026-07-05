import Foundation
import Testing

@testable import Analytics

@Suite("PostHogConfig")
struct PostHogConfigTests {
  @Test("a non-empty API key validates")
  func standard() throws {
    try PostHogConfig(apiKey: "key").validate()
  }

  @Test("an empty API key fails validation")
  func emptyAPIKey() {
    #expect(throws: PostHogConfigError.missingAPIKey) {
      try PostHogConfig().validate()
    }
  }

  @Test("decodes the Go JSON shape (\"apiKey\"/\"endpoint\" keys)")
  func decodesGoShape() throws {
    let config = try JSONDecoder().decode(
      PostHogConfig.self, from: Data(#"{"apiKey":"key","endpoint":"https://eu.posthog.com"}"#.utf8))
    #expect(config.apiKey == "key")
    #expect(config.endpoint == "https://eu.posthog.com")
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = PostHogConfig(apiKey: "key", endpoint: "https://eu.posthog.com")
    let decoded = try JSONDecoder().decode(
      PostHogConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
