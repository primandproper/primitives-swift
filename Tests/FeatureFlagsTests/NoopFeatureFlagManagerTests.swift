import Testing

@testable import FeatureFlags

private func evalContext() -> EvaluationContext {
  EvaluationContext(targetingKey: "user-id")
}

@Suite("NoopFeatureFlagManager")
struct NoopFeatureFlagManagerTests {
  @Test("canUseFeature always returns false")
  func canUseFeatureReturnsFalse() async throws {
    let result = try await NoopFeatureFlagManager().canUseFeature(
      "some-feature", context: evalContext())
    #expect(result == false)
  }

  @Test("stringValue returns the caller's default")
  func stringValueReturnsDefault() async throws {
    let result = try await NoopFeatureFlagManager().stringValue(
      for: "some-feature", default: "fallback", context: evalContext())
    #expect(result == "fallback")
  }

  @Test("int64Value returns the caller's default")
  func int64ValueReturnsDefault() async throws {
    let result = try await NoopFeatureFlagManager().int64Value(
      for: "some-feature", default: 42, context: evalContext())
    #expect(result == 42)
  }

  @Test("float64Value returns the caller's default")
  func float64ValueReturnsDefault() async throws {
    let result = try await NoopFeatureFlagManager().float64Value(
      for: "some-feature", default: 3.14, context: evalContext())
    #expect(result == 3.14)
  }

  @Test("objectValue returns the caller's default")
  func objectValueReturnsDefault() async throws {
    let def: FlagValue = ["k": "v"]
    let result = try await NoopFeatureFlagManager().objectValue(
      for: "some-feature", default: def, context: evalContext())
    #expect(result == def)
  }

  @Test("close never throws")
  func closeSucceeds() async throws {
    try await NoopFeatureFlagManager().close()
  }
}
