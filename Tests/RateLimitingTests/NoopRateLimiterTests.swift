import Testing

@testable import RateLimiting

@Suite("NoopRateLimiter")
struct NoopRateLimiterTests {
  @Test("always allows a single request")
  func alwaysAllowsSingle() async {
    let limiter = NoopRateLimiter()
    for _ in 0..<5 {
      #expect(await limiter.allow(key: "any-key"))
    }
  }

  @Test("always allows a batch of any size")
  func alwaysAllowsBatch() async {
    let limiter = NoopRateLimiter()
    #expect(await limiter.allow(key: "any-key", count: 1_000_000))
  }
}
