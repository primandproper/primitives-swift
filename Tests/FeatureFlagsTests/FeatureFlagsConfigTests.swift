import Foundation
import Testing

@testable import FeatureFlags

@Suite("FeatureFlagProvider")
struct FeatureFlagProviderTests {
  @Test("raw values mirror the Go provider constants")
  func rawValues() {
    #expect(FeatureFlagProvider.launchDarkly.rawValue == "launchdarkly")
    #expect(FeatureFlagProvider.postHog.rawValue == "posthog")
  }
}

@Suite("LaunchDarklyConfig")
struct LaunchDarklyConfigTests {
  @Test("decodes the Go JSON shape")
  func decodesGoShape() throws {
    let json = Data(#"{"sdkKey":"sdk-123","initTimeout":5000000000}"#.utf8)
    let config = try JSONDecoder().decode(LaunchDarklyConfig.self, from: json)
    #expect(config.sdkKey == "sdk-123")
    #expect(config.initTimeout == .seconds(5))
  }

  @Test("missing fields decode to Go's zero values")
  func decodesMissingFields() throws {
    let config = try JSONDecoder().decode(LaunchDarklyConfig.self, from: Data("{}".utf8))
    #expect(config.sdkKey == "")
    #expect(config.initTimeout == .zero)
  }

  @Test("round-trips through JSON as integer nanoseconds")
  func roundTrip() throws {
    let original = LaunchDarklyConfig(sdkKey: "sdk-123", initTimeout: .milliseconds(250))
    let encoded = try JSONEncoder().encode(original)
    #expect(String(decoding: encoded, as: UTF8.self).contains(#""initTimeout":250000000"#))

    let decoded = try JSONDecoder().decode(LaunchDarklyConfig.self, from: encoded)
    #expect(decoded == original)
  }
}

@Suite("PostHogConfig")
struct PostHogConfigTests {
  @Test("decodes the Go JSON shape")
  func decodesGoShape() throws {
    let json = Data(
      #"{"projectAPIKey":"proj","personalAPIKey":"personal","endpoint":"https://eu.posthog.com"}"#
        .utf8)
    let config = try JSONDecoder().decode(PostHogConfig.self, from: json)
    #expect(config.projectAPIKey == "proj")
    #expect(config.personalAPIKey == "personal")
    #expect(config.endpoint == "https://eu.posthog.com")
  }

  @Test("missing fields decode to Go's zero values")
  func decodesMissingFields() throws {
    let config = try JSONDecoder().decode(PostHogConfig.self, from: Data("{}".utf8))
    #expect(config.projectAPIKey == "")
    #expect(config.personalAPIKey == "")
    #expect(config.endpoint == "")
  }

  @Test("a partial payload decodes, defaulting the absent fields")
  func decodesPartialFields() throws {
    let config = try JSONDecoder().decode(
      PostHogConfig.self, from: Data(#"{"projectAPIKey":"proj"}"#.utf8))
    #expect(config.projectAPIKey == "proj")
    #expect(config.personalAPIKey == "")
    #expect(config.endpoint == "")
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = PostHogConfig(projectAPIKey: "proj", personalAPIKey: "personal", endpoint: "")
    let decoded = try JSONDecoder().decode(
      PostHogConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}

@Suite("FeatureFlagsConfig validation")
struct FeatureFlagsConfigValidationTests {
  @Test("a launchdarkly provider with its sub-config validates")
  func launchDarklyValid() throws {
    let config = FeatureFlagsConfig(
      launchDarkly: LaunchDarklyConfig(sdkKey: "key"), provider: "launchdarkly")
    try config.validate()
  }

  @Test("an empty provider validates (resolves to noop)")
  func emptyProviderValid() throws {
    try FeatureFlagsConfig(provider: "").validate()
  }

  @Test("an unrecognized provider fails validation")
  func invalidProviderFails() {
    let config = FeatureFlagsConfig(provider: "invalid_provider")
    #expect(throws: FeatureFlagsError.invalidProvider("invalid_provider")) {
      try config.validate()
    }
  }

  @Test("a posthog provider with its sub-config validates")
  func postHogValid() throws {
    let config = FeatureFlagsConfig(
      postHog: PostHogConfig(projectAPIKey: "p", personalAPIKey: "s"), provider: "posthog")
    try config.validate()
  }

  @Test("a launchdarkly provider missing its sub-config fails validation")
  func launchDarklyMissingConfig() {
    let config = FeatureFlagsConfig(provider: "launchdarkly")
    #expect(throws: FeatureFlagsError.missingProviderConfig(.launchDarkly)) {
      try config.validate()
    }
  }

  @Test("a posthog provider missing its sub-config fails validation")
  func postHogMissingConfig() {
    let config = FeatureFlagsConfig(provider: "posthog")
    #expect(throws: FeatureFlagsError.missingProviderConfig(.postHog)) {
      try config.validate()
    }
  }

  @Test("whitespace/mixed-case provider strings fail strict validation")
  func strictValidationRejectsNormalizableInput() {
    let config = FeatureFlagsConfig(provider: "  LAUNCHDARKLY  ")
    #expect(throws: FeatureFlagsError.invalidProvider("  LAUNCHDARKLY  ")) {
      try config.validate()
    }
  }
}

@Suite("FeatureFlagsConfig.makeFeatureFlagManager")
struct FeatureFlagsConfigFactoryTests {
  @Test("an empty provider builds a noop manager")
  func emptyProviderBuildsNoop() throws {
    let manager = try FeatureFlagsConfig(provider: "").makeFeatureFlagManager()
    #expect(manager is NoopFeatureFlagManager)
  }

  @Test("an unrecognized provider builds a noop manager, matching Go's default case")
  func unknownProviderBuildsNoop() throws {
    let manager = try FeatureFlagsConfig(provider: "something_unknown").makeFeatureFlagManager()
    #expect(manager is NoopFeatureFlagManager)
  }

  @Test("whitespace and mixed case normalize before matching")
  func normalizesProviderString() {
    let config = FeatureFlagsConfig(provider: "  LaunchDarkly  ")
    #expect(throws: FeatureFlagsError.unsupportedProvider(.launchDarkly)) {
      _ = try config.makeFeatureFlagManager()
    }
  }

  @Test(
    "recognized vendor providers are unsupported on this platform",
    arguments: [
      ("launchdarkly", FeatureFlagsError.unsupportedProvider(.launchDarkly)),
      ("posthog", FeatureFlagsError.unsupportedProvider(.postHog)),
    ]
  )
  func recognizedProvidersThrow(provider: String, expected: FeatureFlagsError) {
    let config = FeatureFlagsConfig(provider: provider)
    #expect(throws: expected) {
      _ = try config.makeFeatureFlagManager()
    }
  }
}

@Suite("FeatureFlagsConfig Codable")
struct FeatureFlagsConfigCodableTests {
  @Test("decodes the Go JSON shape, including the \"posthog\" key")
  func decodesGoShape() throws {
    let json = Data(
      #"""
      {
        "launchDarkly": {"sdkKey": "sdk-key", "initTimeout": 0},
        "posthog": {"projectAPIKey": "proj", "personalAPIKey": "personal", "endpoint": ""},
        "provider": "launchdarkly"
      }
      """#.utf8)

    let config = try JSONDecoder().decode(FeatureFlagsConfig.self, from: json)
    #expect(config.provider == "launchdarkly")
    #expect(config.launchDarkly?.sdkKey == "sdk-key")
    #expect(config.postHog?.projectAPIKey == "proj")
  }

  @Test("ignores an unrecognized circuitBreakerConfig key without failing to decode")
  func ignoresExtraCircuitBreakerKey() throws {
    let json = Data(
      #"""
      {
        "provider": "",
        "circuitBreakerConfig": {"name": "ff", "circuitBreakerErrorPercentage": 50}
      }
      """#.utf8)

    let config = try JSONDecoder().decode(FeatureFlagsConfig.self, from: json)
    #expect(config.provider == "")
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = FeatureFlagsConfig(
      launchDarkly: LaunchDarklyConfig(sdkKey: "sdk-key"),
      postHog: PostHogConfig(projectAPIKey: "proj", personalAPIKey: "personal"),
      provider: "launchdarkly")
    let decoded = try JSONDecoder().decode(
      FeatureFlagsConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}

@Suite("FeatureFlagsError messages")
struct FeatureFlagsErrorTests {
  @Test("messages name the offending provider or value")
  func messages() {
    #expect(
      FeatureFlagsError.invalidProvider("bogus").errorDescription
        == "invalid feature flag provider: bogus")
    #expect(
      FeatureFlagsError.missingProviderConfig(.launchDarkly).errorDescription
        == "missing configuration for feature flag provider: launchdarkly")
    #expect(
      FeatureFlagsError.unsupportedProvider(.postHog).errorDescription
        == "unsupported feature flag provider: posthog")
  }
}
