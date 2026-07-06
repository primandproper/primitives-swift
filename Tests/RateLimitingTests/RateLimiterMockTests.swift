import Testing

@testable import RateLimiting

@Suite("RateLimiterMock")
struct RateLimiterMockTests {
  @Test("defaults to allowing every call when no handler is set")
  func defaultsToAllow() async {
    let mock = RateLimiterMock()
    #expect(await mock.allow(key: "user-1"))
    #expect(await mock.allow(key: "user-1", count: 5))
  }

  @Test("records every call in order")
  func recordsCalls() async {
    let mock = RateLimiterMock()
    _ = await mock.allow(key: "user-1")
    _ = await mock.allow(key: "user-2", count: 3)

    let calls = await mock.allowCalls
    #expect(
      calls == [
        RateLimiterMock.AllowCall(key: "user-1", count: 1),
        RateLimiterMock.AllowCall(key: "user-2", count: 3),
      ])
  }

  @Test("defers to the injected handler")
  func usesHandler() async {
    let mock = RateLimiterMock { key, count in
      key == "throttled" && count <= 1 ? false : true
    }

    #expect(await !mock.allow(key: "throttled"))
    #expect(await mock.allow(key: "unthrottled"))
  }
}
