import Testing

@testable import FeatureFlags

private struct Boom: Error, Equatable {}

private func evalContext(_ key: String = "user123") -> EvaluationContext {
  EvaluationContext(targetingKey: key)
}

@Suite("FeatureFlagManagerMock")
struct FeatureFlagManagerMockTests {
  @Test("canUseFeature invokes the configured handler and records the call")
  func canUseFeature() async throws {
    let mock = FeatureFlagManagerMock(canUseFeature: { feature, context in
      #expect(feature == "dark-mode")
      #expect(context.targetingKey == "user123")
      return true
    })

    let result = try await mock.canUseFeature("dark-mode", context: evalContext())
    #expect(result == true)

    let calls = await mock.canUseFeatureCalls
    #expect(calls.count == 1)
    #expect(calls[0].feature == "dark-mode")
  }

  @Test("canUseFeature propagates a thrown error from the handler")
  func canUseFeatureThrows() async {
    let mock = FeatureFlagManagerMock(canUseFeature: { _, _ in throw Boom() })

    await #expect(throws: Boom.self) {
      _ = try await mock.canUseFeature("some-feature", context: evalContext())
    }
  }

  @Test("stringValue invokes the configured handler and records the call")
  func stringValue() async throws {
    let mock = FeatureFlagManagerMock(stringValue: { _, defaultValue, _ in
      "resolved-" + defaultValue
    })

    let result = try await mock.stringValue(
      for: "string-flag", default: "fallback", context: evalContext())
    #expect(result == "resolved-fallback")

    let calls = await mock.stringValueCalls
    #expect(calls.count == 1)
    #expect(calls[0].defaultValue == "fallback")
  }

  @Test("int64Value invokes the configured handler and records the call")
  func int64Value() async throws {
    let mock = FeatureFlagManagerMock(int64Value: { _, _, _ in 42 })

    let result = try await mock.int64Value(for: "int-flag", default: 0, context: evalContext())
    #expect(result == 42)
    #expect(await mock.int64ValueCalls.count == 1)
  }

  @Test("float64Value invokes the configured handler and records the call")
  func float64Value() async throws {
    let mock = FeatureFlagManagerMock(float64Value: { _, _, _ in 3.14 })

    let result = try await mock.float64Value(for: "float-flag", default: 0, context: evalContext())
    #expect(result == 3.14)
    #expect(await mock.float64ValueCalls.count == 1)
  }

  @Test("objectValue invokes the configured handler and records the call")
  func objectValue() async throws {
    let expected: FlagValue = ["key": "value"]
    let mock = FeatureFlagManagerMock(objectValue: { _, _, _ in expected })

    let result = try await mock.objectValue(
      for: "object-flag", default: ["default": true], context: evalContext())
    #expect(result == expected)
    #expect(await mock.objectValueCalls.count == 1)
  }

  @Test("close invokes the configured handler and records the call")
  func close() async throws {
    let mock = FeatureFlagManagerMock(close: {})

    try await mock.close()
    #expect(await mock.closeCallCount == 1)
  }
}
