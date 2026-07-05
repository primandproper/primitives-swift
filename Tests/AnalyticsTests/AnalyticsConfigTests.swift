import Foundation
import Testing

@testable import Analytics

@Suite("AnalyticsConfig validation")
struct AnalyticsConfigValidationTests {
  @Test("a valid top-level provider validates")
  func standard() throws {
    let config = AnalyticsConfig(
      source: SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment"))
    try config.validate()
  }

  @Test("an empty top-level provider validates (unlike SourceConfig, it is not required)")
  func emptyProviderIsFine() throws {
    try AnalyticsConfig().validate()
  }

  @Test("an invalid top-level provider's credentials fail validation")
  func invalidTopLevelToken() {
    let config = AnalyticsConfig(source: SourceConfig(provider: "segment"))
    #expect(throws: SourceConfigError.missingProviderConfig(.segment)) {
      try config.validate()
    }
  }

  @Test("an invalid proxy source fails validation, wrapped with its source name")
  func rejectsInvalidProxySource() {
    let config = AnalyticsConfig(
      proxySources: ProxySourcesConfig(web: SourceConfig(provider: "segment")),
      source: SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment"))

    #expect(
      throws: AnalyticsConfigError.invalidProxySource(
        name: "web", underlying: .missingProviderConfig(.segment))
    ) {
      try config.validate()
    }
  }

  @Test("a valid proxy source validates alongside a valid top-level source")
  func acceptsValidProxySource() throws {
    let config = AnalyticsConfig(
      proxySources: ProxySourcesConfig(
        web: SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment")),
      source: SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment"))

    try config.validate()
  }
}

@Suite("AnalyticsConfig Codable (Go's flattened embedding)")
struct AnalyticsConfigCodableTests {
  @Test("decodes the Go JSON shape: source fields flattened at the top level")
  func decodesGoShape() throws {
    let json = Data(
      #"""
      {
        "proxySources": {"ios": {"provider": "posthog", "posthog": {"apiKey": "key"}}},
        "segment": null,
        "posthog": {"apiKey": "top-level-key"},
        "provider": "posthog",
        "circuitBreaker": {"name": "UNKNOWN"}
      }
      """#.utf8)

    let config = try JSONDecoder().decode(AnalyticsConfig.self, from: json)

    #expect(config.source.provider == "posthog")
    #expect(config.source.posthog == PostHogConfig(apiKey: "top-level-key"))
    #expect(config.proxySources.ios?.provider == "posthog")
    #expect(config.proxySources.ios?.posthog == PostHogConfig(apiKey: "key"))
  }

  @Test("encodes the source fields at the top level, not nested under \"source\"")
  func encodesFlattened() throws {
    let config = AnalyticsConfig(source: SourceConfig(provider: "segment"))
    let data = try JSONEncoder().encode(config)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(object?["provider"] as? String == "segment")
    #expect(object?["proxySources"] != nil)
    #expect(object?["source"] == nil)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = AnalyticsConfig(
      proxySources: ProxySourcesConfig(ios: SourceConfig(provider: "posthog")),
      source: SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment"))
    let decoded = try JSONDecoder().decode(
      AnalyticsConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }

  @Test("ensureDefaults fills in the top-level and every proxy source's circuit breaker")
  func ensureDefaults() {
    var config = AnalyticsConfig(
      proxySources: ProxySourcesConfig(ios: SourceConfig(provider: "posthog")),
      source: SourceConfig(provider: "segment"))
    config.ensureDefaults()

    #expect(config.source.circuitBreaker.name == "UNKNOWN")
    #expect(config.proxySources.ios?.circuitBreaker.name == "UNKNOWN")
  }
}
