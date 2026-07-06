import Foundation
import Observability

/// An **actor-backed** in-memory ``BatchCache``, ported from platform-go's `memory.inMemoryCacheImpl`
/// and extended per the port spec with **TTL expiry** and **LRU eviction** (Go's map had neither).
///
/// Go guarded a `map` with a `sync.RWMutex`; the Swift port uses an `actor` for the same mutual
/// exclusion without hand-rolled locks. Two behaviors go beyond the Go origin:
///   * **TTL.** Each entry records an `expiresAt` computed at write time from ``expiry`` (a `Duration`).
///     A `get` for an expired entry evicts it and reads as a miss. `expiry <= .zero` disables TTL
///     (entries never expire), matching a Go zero-`Duration` "no expiry" reading.
///   * **LRU.** When ``maxEntries`` is positive and a write pushes the count over it, the
///     least-recently-used key is evicted. `maxEntries == 0` means unbounded, matching Go's uncapped map.
///
/// Observability threads through an injected ``Observability/Pillars`` (SVC-10 rule): each operation
/// opens a span via a ``LiveObserver`` and increments the same hit/miss/set/delete counters and latency
/// histogram Go emitted (`in_memory_cache_cache_*`).
public actor InMemoryCache<Value: Codable & Sendable>: BatchCache {
  private struct Entry {
    var value: Value
    /// Absolute expiry instant, or `nil` when TTL is disabled.
    var expiresAt: Date?
  }

  private var entries: [String: Entry] = [:]
  /// Keys ordered least-recently-used (front) to most-recently-used (back). Kept in step with
  /// ``entries`` so eviction is O(1) at the head.
  private var useOrder: [String] = []

  private let maxEntries: Int
  private let expiry: Duration
  private let now: @Sendable () -> Date
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let metricName: String

  /// - Parameters:
  ///   - expiry: per-entry time-to-live. `<= .zero` disables expiry. Defaults to one hour, matching Go's
  ///     `envDefault:"1h"`.
  ///   - maxEntries: LRU capacity; `0` (the default) is unbounded, matching Go's uncapped map.
  ///   - name: observability/metric prefix. Defaults to Go's `const name = "in_memory_cache"`.
  ///   - pillars: observability pillars; side effects open spans/metrics through these. Defaults to
  ///     ``Observability/Pillars/noop``.
  ///   - now: clock seam for TTL, injectable so tests advance time without sleeping. Defaults to
  ///     `Date.init`.
  public init(
    expiry: Duration = .seconds(3600),
    maxEntries: Int = 0,
    name: String = "in_memory_cache",
    pillars: Pillars = .noop,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.expiry = expiry
    self.maxEntries = max(0, maxEntries)
    self.metricName = name
    self.observer = LiveObserver(name: name, logger: pillars.logger, tracer: pillars.tracer)
    self.metrics = pillars.metrics
    self.now = now
  }

  // The `begin`/`end` span form is used (rather than `observer.operation { … }`) because these bodies
  // touch actor-isolated state: a `self`-isolated closure can't be sent to the nonisolated `operation`
  // under Swift 6. `begin` returns a `Sendable` ``Operation`` we drive inline in the actor's context.

  public func get(_ key: String) async throws -> Value? {
    let op = observer.begin("cache.get")
    op.set("cache.key", key)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    guard let entry = entries[key] else {
      metrics.counter("\(metricName)_cache_misses").increment()
      return nil
    }
    if isExpired(entry) {
      remove(key)
      metrics.counter("\(metricName)_cache_misses").increment()
      return nil
    }
    touch(key)
    metrics.counter("\(metricName)_cache_hits").increment()
    return entry.value
  }

  public func set(_ key: String, to value: Value) async throws {
    let op = observer.begin("cache.set")
    op.set("cache.key", key)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    entries[key] = Entry(value: value, expiresAt: expiryInstant())
    touch(key)
    evictIfNeeded()
    metrics.counter("\(metricName)_cache_sets").increment()
  }

  public func delete(_ key: String) async throws {
    let op = observer.begin("cache.delete")
    op.set("cache.key", key)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    remove(key)
    metrics.counter("\(metricName)_cache_deletes").increment()
  }

  public func getMany(_ keys: [String]) async throws -> [String: Value] {
    let op = observer.begin("cache.getMany")
    op.set("cache.length", keys.count)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    var out: [String: Value] = [:]
    out.reserveCapacity(keys.count)
    for key in keys {
      guard let entry = entries[key] else {
        metrics.counter("\(metricName)_cache_misses").increment()
        continue
      }
      if isExpired(entry) {
        remove(key)
        metrics.counter("\(metricName)_cache_misses").increment()
        continue
      }
      touch(key)
      out[key] = entry.value
      metrics.counter("\(metricName)_cache_hits").increment()
    }
    return out
  }

  public func setMany(_ items: [String: Value]) async throws {
    let op = observer.begin("cache.setMany")
    op.set("cache.length", items.count)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    let expiresAt = expiryInstant()
    for (key, value) in items {
      entries[key] = Entry(value: value, expiresAt: expiresAt)
      touch(key)
      metrics.counter("\(metricName)_cache_sets").increment()
    }
    evictIfNeeded()
  }

  public func ping() async throws {
    let op = observer.begin("cache.ping")
    defer { op.end() }
    op.logger.debug("ping")
  }

  // MARK: - Internals

  /// Test/inspection seam: the current live (non-expired-lazily-purged) entry count.
  public var count: Int { entries.count }

  private func expiryInstant() -> Date? {
    expiry <= .zero ? nil : now().addingTimeInterval(expiry.timeIntervalValue)
  }

  private func isExpired(_ entry: Entry) -> Bool {
    guard let expiresAt = entry.expiresAt else { return false }
    return now() >= expiresAt
  }

  /// Marks `key` most-recently-used.
  private func touch(_ key: String) {
    if let idx = useOrder.firstIndex(of: key) {
      useOrder.remove(at: idx)
    }
    useOrder.append(key)
  }

  private func remove(_ key: String) {
    entries[key] = nil
    if let idx = useOrder.firstIndex(of: key) {
      useOrder.remove(at: idx)
    }
  }

  private func evictIfNeeded() {
    guard maxEntries > 0 else { return }
    while entries.count > maxEntries, let victim = useOrder.first {
      remove(victim)
    }
  }

  private func recordLatency(since start: ContinuousClock.Instant) {
    let elapsedMillis = start.duration(to: .now).timeIntervalValue * 1000
    metrics.histogram("\(metricName)_cache_latency_ms").record(elapsedMillis)
  }
}
