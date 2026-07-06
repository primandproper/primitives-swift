import Encoding
import Foundation
import Observability

/// An **actor-backed** disk ``BatchCache`` layer: one file per key under a directory, values encoded
/// through the ``Encoding`` module. This is a port-spec addition (Go's cache had only memory + Redis);
/// it fills the "persistent local cache" slot Redis held server-side, with no network dependency.
///
/// Each entry is stored as a ``DiskEnvelope`` — the value plus an optional absolute `expiresAt` — encoded
/// by an injected ``Encoding/ClientEncoder`` (JSON by default, so files round-trip with a Go peer's
/// JSON). A `get` on a file whose `expiresAt` has passed deletes the file and reads as a miss. Keys are
/// mapped to filenames by URL-safe base64 of their UTF-8 bytes, so arbitrary key strings (slashes,
/// spaces) never produce an illegal path.
///
/// FileManager IO and codec failures surface as ``CacheError`` (`.io`, `.encoding`, `.decoding`) rather
/// than crashing — the seam a remote adapter would also need. Observability threads through
/// ``Observability/Pillars`` exactly as ``InMemoryCache`` does.
public actor DiskCache<Value: Codable & Sendable>: BatchCache {
  /// The on-disk record: the cached value plus its expiry. Encoded/decoded by ``encoder``.
  struct DiskEnvelope: Codable {
    var value: Value
    /// Absolute expiry instant, or `nil` when TTL is disabled.
    var expiresAt: Date?
  }

  private let directory: URL
  private let expiry: Duration
  private let encoder: any ClientEncoder
  private let now: @Sendable () -> Date
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let metricName: String

  /// - Parameters:
  ///   - directory: the folder entries are written under. Created (with intermediates) if absent; a
  ///     failure to create it throws ``CacheError/io(_:)``.
  ///   - expiry: per-entry TTL. `<= .zero` disables expiry. Defaults to one hour.
  ///   - name: observability/metric prefix. Defaults to `"disk_cache"`.
  ///   - pillars: observability pillars. Defaults to ``Observability/Pillars/noop``.
  ///   - encoder: codec values are encoded through. Defaults to ``Encoding/JSONClientEncoder``.
  ///   - now: clock seam for TTL, injectable for tests. Defaults to `Date.init`.
  public init(
    directory: URL,
    expiry: Duration = .seconds(3600),
    name: String = "disk_cache",
    pillars: Pillars = .noop,
    encoder: any ClientEncoder = JSONClientEncoder(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    self.directory = directory
    self.expiry = expiry
    self.encoder = encoder
    self.metricName = name
    self.observer = LiveObserver(name: name, logger: pillars.logger, tracer: pillars.tracer)
    self.metrics = pillars.metrics
    self.now = now

    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
    } catch {
      throw CacheError.io("creating cache directory: \(error)")
    }
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
    return try read(key)
  }

  public func set(_ key: String, to value: Value) async throws {
    let op = observer.begin("cache.set")
    op.set("cache.key", key)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }
    try write(key, value)
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
    try removeFile(key)
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
      if let value = try read(key) {
        out[key] = value
      }
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
    for (key, value) in items {
      try write(key, value)
      metrics.counter("\(metricName)_cache_sets").increment()
    }
  }

  public func ping() async throws {
    let op = observer.begin("cache.ping")
    defer { op.end() }
    // Reachability for a disk cache is "is the directory writable?" — Go's Ping was a no-op success.
    guard FileManager.default.isWritableFile(atPath: directory.path) else {
      throw op.error(CacheError.io("cache directory not writable"), "ping")
    }
  }

  // MARK: - Internals

  private func read(_ key: String) throws -> Value? {
    let url = fileURL(for: key)
    guard let data = FileManager.default.contents(atPath: url.path) else {
      metrics.counter("\(metricName)_cache_misses").increment()
      return nil
    }
    let envelope: DiskEnvelope
    do {
      envelope = try encoder.decode(DiskEnvelope.self, from: data)
    } catch {
      throw CacheError.decoding("\(error)")
    }
    if let expiresAt = envelope.expiresAt, now() >= expiresAt {
      try removeFile(key)
      metrics.counter("\(metricName)_cache_misses").increment()
      return nil
    }
    metrics.counter("\(metricName)_cache_hits").increment()
    return envelope.value
  }

  private func write(_ key: String, _ value: Value) throws {
    let expiresAt = expiry <= .zero ? nil : now().addingTimeInterval(expiry.timeIntervalValue)
    let envelope = DiskEnvelope(value: value, expiresAt: expiresAt)
    let data: Data
    do {
      data = try encoder.encode(envelope)
    } catch {
      throw CacheError.encoding("\(error)")
    }
    do {
      try data.write(to: fileURL(for: key), options: .atomic)
    } catch {
      throw CacheError.io("writing \(key): \(error)")
    }
  }

  private func removeFile(_ key: String) throws {
    let url = fileURL(for: key)
    do {
      try FileManager.default.removeItem(at: url)
    } catch CocoaError.fileNoSuchFile {
      // A missing key is not an error, matching Go's `delete`.
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      // Same, via the NSError shape some FileManager failures surface as.
    } catch {
      throw CacheError.io("deleting \(key): \(error)")
    }
  }

  private func fileURL(for key: String) -> URL {
    let name = Data(key.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return directory.appendingPathComponent(name, isDirectory: false)
  }

  private func recordLatency(since start: ContinuousClock.Instant) {
    let elapsedMillis = start.duration(to: .now).timeIntervalValue * 1000
    metrics.histogram("\(metricName)_cache_latency_ms").record(elapsedMillis)
  }
}
