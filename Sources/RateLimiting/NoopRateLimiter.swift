/// A ``RateLimiter`` that always allows — ported from platform-go's `ratelimiting/noop` subpackage.
///
/// The always-safe fallback returned when rate limiting is disabled or misconfigured — matching Go's
/// `noop.NewRateLimiter()`, which ``RateLimitingConfig`` reaches for on an empty/`"noop"` provider or an
/// unrecognized one.
///
/// Because it holds no state it is trivially `Sendable`, and its synchronous method body satisfies the
/// protocol's `async` requirement (a non-`async` method fulfills an `async` requirement).
public struct NoopRateLimiter: RateLimiter {
  public init() {}

  public func allow(key: String, count: Int) -> Bool { true }
}
