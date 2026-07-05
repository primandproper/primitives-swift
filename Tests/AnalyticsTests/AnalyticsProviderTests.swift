import Testing

@testable import Analytics

@Suite("AnalyticsProvider")
struct AnalyticsProviderTests {
  @Test("raw values mirror the Go provider strings")
  func rawValues() {
    #expect(AnalyticsProvider.segment.rawValue == "segment")
    #expect(AnalyticsProvider.posthog.rawValue == "posthog")
  }
}

@Suite("AnalyticsError messages")
struct AnalyticsErrorTests {
  @Test("message names the offending provider", arguments: [AnalyticsProvider.segment, .posthog])
  func message(provider: AnalyticsProvider) {
    #expect(
      AnalyticsError.unsupportedProvider(provider).errorDescription?.contains(provider.rawValue) == true)
  }
}
