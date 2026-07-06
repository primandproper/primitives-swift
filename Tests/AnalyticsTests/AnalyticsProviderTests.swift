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
