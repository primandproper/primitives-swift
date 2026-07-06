/// A generic key/value cache, ported from platform-go's `cache.Cache[T]` (`cache/cache.go`).
///
/// **Idiomatic mapping of the Go interface.** Go's `Get` returns `(*T, error)` and signals a miss with
/// the sentinel `cache.ErrNotFound`. A pointer-or-sentinel is Swift's `Optional`, so ``get(_:)`` returns
/// `Value?` — `nil` *is* the miss, mirroring how ``BatchCache/getMany(_:)`` simply omits absent keys from
/// its result map. ``CacheError/notFound`` is still shipped for callers that prefer a throwing sentinel,
/// but the seam itself never throws it. `context.Context` is dropped (every module in this port drops
/// it); observability rides an injected ``Observability/Pillars`` instead.
///
/// The value type is `Codable & Sendable` — narrower than Go's `any` — because the disk provider must
/// encode values through the ``Encoding`` module and every conformer is `Sendable` under Swift 6.
public protocol Cache<Value>: Sendable {
  associatedtype Value: Codable & Sendable

  /// Fetches `key`, returning `nil` on a miss (Go's `ErrNotFound`). An expired entry reads as a miss.
  func get(_ key: String) async throws -> Value?

  /// Stores `value` at `key` with the cache's configured expiry.
  func set(_ key: String, to value: Value) async throws

  /// Removes `key`. A missing key is not an error, matching Go's `delete`.
  func delete(_ key: String) async throws

  /// Liveness probe, ported from Go's `Ping`. Local providers always succeed; the seam exists so a
  /// future remote (Redis) adapter can report an unreachable backend.
  func ping() async throws
}

/// A ``Cache`` that also supports batched reads and writes, ported from platform-go's
/// `cache.BatchCache[T]`.
///
/// Go documents that "not every Cache implementation supports batching, so callers should obtain a
/// BatchCache via a type assertion." Swift's analogue is `as? any BatchCache<Value>`. Every conformer in
/// this port happens to be a `BatchCache`, but the split is preserved so a future non-batching remote
/// adapter can conform to ``Cache`` alone.
public protocol BatchCache<Value>: Cache {
  /// Fetches multiple keys at once. Missing (or expired) keys are omitted from the returned map, so a
  /// key's absence from the result is a cache miss — verbatim Go semantics.
  func getMany(_ keys: [String]) async throws -> [String: Value]

  /// Stores multiple values at once, each with the cache's configured expiry.
  func setMany(_ items: [String: Value]) async throws
}
