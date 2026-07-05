import CircuitBreaking
import Foundation
import Testing

@testable import Analytics

@Suite("SourceConfig validation")
struct SourceConfigValidationTests {
  @Test("a fully-configured segment source validates")
  func standardSegment() throws {
    let config = SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment")
    try config.validate()
  }

  @Test("a fully-configured posthog source validates")
  func standardPostHog() throws {
    let config = SourceConfig(posthog: PostHogConfig(apiKey: "key"), provider: "posthog")
    try config.validate()
  }

  @Test("an empty provider fails validation")
  func emptyProvider() {
    #expect(throws: SourceConfigError.providerRequired) {
      try SourceConfig().validate()
    }
  }

  @Test("an unrecognized provider fails validation")
  func unrecognizedProvider() {
    #expect(throws: SourceConfigError.unknownProvider("bogus")) {
      try SourceConfig(provider: "bogus").validate()
    }
  }

  @Test("segment provider with no segment config fails validation")
  func segmentMissingConfig() {
    #expect(throws: SourceConfigError.missingProviderConfig(.segment)) {
      try SourceConfig(provider: "segment").validate()
    }
  }

  @Test("posthog provider with no posthog config fails validation")
  func postHogMissingConfig() {
    #expect(throws: SourceConfigError.missingProviderConfig(.posthog)) {
      try SourceConfig(provider: "posthog").validate()
    }
  }

  @Test("segment provider with an invalid segment config fails validation")
  func segmentInvalidConfig() {
    #expect(throws: SourceConfigError.invalidSegmentConfig(.missingAPIToken)) {
      try SourceConfig(segment: SegmentConfig(), provider: "segment").validate()
    }
  }

  @Test("posthog provider with an invalid posthog config fails validation")
  func postHogInvalidConfig() {
    #expect(throws: SourceConfigError.invalidPostHogConfig(.missingAPIKey)) {
      try SourceConfig(posthog: PostHogConfig(), provider: "posthog").validate()
    }
  }

  @Test("provider matching is case-insensitive and trims whitespace")
  func resolvedProviderLenient() {
    #expect(SourceConfig(provider: "  SEGMENT  ").resolvedProvider == .segment)
    #expect(SourceConfig(provider: "PostHog").resolvedProvider == .posthog)
    #expect(SourceConfig(provider: "").resolvedProvider == nil)
  }
}

@Suite("SourceConfig.provideCollector")
struct SourceConfigProvideCollectorTests {
  @Test(
    "a recognized, fully-configured provider throws unsupportedProvider (no iOS SDK)",
    arguments: [
      (SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment"), AnalyticsProvider.segment),
      (SourceConfig(posthog: PostHogConfig(apiKey: "key"), provider: "posthog"), AnalyticsProvider.posthog),
    ])
  func recognizedProvidersThrow(config: SourceConfig, provider: AnalyticsProvider) {
    #expect(throws: AnalyticsError.unsupportedProvider(provider)) {
      _ = try config.provideCollector()
    }
  }

  @Test("segment provider with a nil segment config throws missingProviderConfig")
  func segmentMissingConfigThrows() {
    #expect(throws: SourceConfigError.missingProviderConfig(.segment)) {
      _ = try SourceConfig(provider: "segment").provideCollector()
    }
  }

  @Test("posthog provider with a nil posthog config throws missingProviderConfig")
  func postHogMissingConfigThrows() {
    #expect(throws: SourceConfigError.missingProviderConfig(.posthog)) {
      _ = try SourceConfig(provider: "posthog").provideCollector()
    }
  }

  @Test("an unrecognized provider returns a working noop reporter")
  func unrecognizedProviderReturnsNoop() async throws {
    let reporter = try SourceConfig(provider: "bogus").provideCollector()
    try await reporter.eventOccurred(event: "e", userID: "u", properties: [:])
  }

  @Test("an empty provider returns a working noop reporter")
  func emptyProviderReturnsNoop() async throws {
    let reporter = try SourceConfig().provideCollector()
    try await reporter.eventOccurred(event: "e", userID: "u", properties: [:])
  }
}

@Suite("SourceConfig defaults and Codable")
struct SourceConfigDefaultsTests {
  @Test("ensureDefaults fills in the embedded circuit breaker config")
  func ensureDefaults() {
    var config = SourceConfig(provider: "segment")
    config.ensureDefaults()

    #expect(config.circuitBreaker.name == "UNKNOWN")
    #expect(config.circuitBreaker.errorRate == 100)
    #expect(config.circuitBreaker.minimumSampleThreshold == 20)
  }

  @Test("ensuringDefaults returns a defaulted copy without mutating the original")
  func ensuringDefaultsCopy() {
    let original = SourceConfig(provider: "segment")
    let defaulted = original.ensuringDefaults()

    #expect(original.circuitBreaker.name.isEmpty)
    #expect(defaulted.circuitBreaker.name == "UNKNOWN")
  }

  @Test("decodes the Go JSON shape, including the nested circuitBreaker config")
  func decodesGoShape() throws {
    let json = Data(
      #"""
      {
        "segment": {"apiToken": "tok"},
        "posthog": null,
        "provider": "segment",
        "circuitBreaker": {
          "name": "analytics",
          "circuitBreakerErrorPercentage": 50,
          "circuitBreakerMinimumOccurrenceThreshold": 10
        }
      }
      """#.utf8)

    let config = try JSONDecoder().decode(SourceConfig.self, from: json)

    #expect(config.provider == "segment")
    #expect(config.segment == SegmentConfig(apiToken: "tok"))
    #expect(config.posthog == nil)
    #expect(config.circuitBreaker.name == "analytics")
    #expect(config.circuitBreaker.errorRate == 50)
    #expect(config.circuitBreaker.minimumSampleThreshold == 10)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = SourceConfig(
      segment: SegmentConfig(apiToken: "tok"), provider: "segment",
      circuitBreaker: CircuitBreakerConfig(name: "analytics", errorRate: 50, minimumSampleThreshold: 10))
    let decoded = try JSONDecoder().decode(
      SourceConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
