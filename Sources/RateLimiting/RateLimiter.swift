import Foundation

/// Limits the rate of operations per key — ported from platform-go's `ratelimiting.RateLimiter`
/// interface.
///
/// Go's interface is two synchronous methods, `Allow(ctx, key) (bool, error)` and `Close() error`,
/// backed by a `sync.Map` of per-key `golang.org/x/time/rate.Limiter`s. The port keeps the "check one
/// key" surface but reshapes it for Swift:
///
/// - **No `Close()`.** Go's in-memory backend used `Close()` only to drop the per-key map so it didn't
///   retain memory past shutdown; a Swift actor has no such "closed" lifecycle to enforce, and its
///   stored dictionary is reclaimed with the actor itself. ``TokenBucketRateLimiter`` still exposes a
///   ``TokenBucketRateLimiter/reset()`` for a caller that wants to drop accumulated per-key state
///   without discarding the limiter.
/// - **No thrown `Error`.** The only backend that ever produced a non-nil error was the Redis-backed
///   sliding-window limiter (a network failure calling `EVAL`), and per the port's native-seam rule that
///   backend is dropped entirely — see ``RateLimitingConfig``. The remaining backends (in-memory,
///   no-op) never fail, so `allow` simply returns `Bool`.
/// - **`allow(key:count:)` replaces a bare `Allow`.** This is the Swift-native token-bucket primitive:
///   Go's `rate.Limiter` also exposes `AllowN` (consume `n` tokens atomically) even though
///   `ratelimiting.RateLimiter` never surfaced it. The port promotes it to the seam itself, since a
///   client throttling a batch operation wants to charge it as more than one request.
///   ``allow(key:)`` is the single-token convenience, matching Go's `Allow`.
public protocol RateLimiter: Sendable {
  /// Reports whether `count` operations for `key` may proceed right now, atomically debiting `count`
  /// tokens from that key's bucket if — and only if — the answer is `true` (no partial debits on a
  /// rejection). Mirrors the *behavior* of `golang.org/x/time/rate.Limiter.AllowN`, generalized to a
  /// per-key store the way `ratelimiting.RateLimiter.Allow` was.
  func allow(key: String, count: Int) async -> Bool
}

extension RateLimiter {
  /// Single-token convenience — the direct analogue of Go's `Allow(ctx, key)`.
  public func allow(key: String) async -> Bool {
    await allow(key: key, count: 1)
  }
}
