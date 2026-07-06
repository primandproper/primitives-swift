/// A no-op ``BatchCache``, ported from platform-go's `noop.Cache[T]` (`cache/noop/noop.go`).
///
/// Every read is a miss and every write is discarded — the always-safe placeholder when a component
/// wants a cache-shaped dependency but no real storage. A value type (no shared mutable state), so it is
/// trivially `Sendable`; no actor needed.
public struct NoopCache<Value: Codable & Sendable>: BatchCache {
  public init() {}

  /// Always a miss (`nil`), mirroring Go returning `ErrNotFound`.
  public func get(_ key: String) async throws -> Value? { nil }

  /// Discards the write.
  public func set(_ key: String, to value: Value) async throws {}

  /// No-op.
  public func delete(_ key: String) async throws {}

  /// Always an empty map, mirroring Go's `GetMany` returning `map[string]*T{}`.
  public func getMany(_ keys: [String]) async throws -> [String: Value] { [:] }

  /// Discards the writes.
  public func setMany(_ items: [String: Value]) async throws {}

  /// Always succeeds.
  public func ping() async throws {}
}
