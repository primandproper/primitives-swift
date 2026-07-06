/// A configurable ``RateLimiter`` test double, the Swift analogue of a moq-generated mock (platform-go
/// doesn't ship one for `ratelimiting.RateLimiter`, but the shape mirrors
/// ``FeatureFlags/FeatureFlagManagerMock`` and ``Analytics/EventReporterMock``, which do).
///
/// An `actor` so its recorded calls are race-free. The handler closure is `let`, injected once at
/// ``init``: under Swift 6 actor isolation a `public var` on an actor cannot be assigned from another
/// isolation domain (`mock.allowHandler = …` would be a cross-actor mutation error), so configuration
/// happens at construction time.
///
/// An unset handler defaults to always allowing — the permissive default a test that isn't exercising
/// rate limiting can rely on without stubbing anything, matching how ``NoopRateLimiter`` behaves.
public actor RateLimiterMock: RateLimiter {
  /// One recorded ``allow(key:count:)`` invocation, in call order.
  public struct AllowCall: Sendable, Equatable {
    public let key: String
    public let count: Int
  }

  private let allowHandler: (@Sendable (String, Int) async -> Bool)?

  public private(set) var allowCalls: [AllowCall] = []

  /// - Parameter allowHandler: computes the answer for each ``allow(key:count:)`` call. Left `nil`
  ///   (the default), every call is allowed.
  public init(allowHandler: (@Sendable (String, Int) async -> Bool)? = nil) {
    self.allowHandler = allowHandler
  }

  public func allow(key: String, count: Int) async -> Bool {
    allowCalls.append(AllowCall(key: key, count: count))
    guard let allowHandler else { return true }
    return await allowHandler(key, count)
  }
}
