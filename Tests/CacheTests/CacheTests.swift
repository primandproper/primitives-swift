import Encoding
import Foundation
import Observability
import XCTest

@testable import Cache

/// A mutable, thread-safe clock for TTL tests: start at a fixed instant, advance manually, no sleeping.
private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date
  init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }
  var now: @Sendable () -> Date { { [self] in lock.withLock { current } } }
  func advance(_ interval: TimeInterval) {
    lock.withLock { current = current.addingTimeInterval(interval) }
  }
}

private struct Widget: Codable, Equatable, Sendable {
  var id: Int
  var name: String
}

/// A ``ClientEncoder`` that counts calls and delegates to ``JSONClientEncoder``, proving ``DiskCache``
/// encodes through the injected ``Encoding`` codec.
private final class CountingEncoder: ClientEncoder, @unchecked Sendable {
  let contentType: ContentType = .json
  private let backing = JSONClientEncoder()
  private let lock = NSLock()
  private var _encodeCount = 0
  private var _decodeCount = 0
  var encodeCount: Int { lock.withLock { _encodeCount } }
  var decodeCount: Int { lock.withLock { _decodeCount } }

  func encode<T: Encodable>(_ value: T) throws -> Data {
    lock.withLock { _encodeCount += 1 }
    return try backing.encode(value)
  }

  func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    lock.withLock { _decodeCount += 1 }
    return try backing.decode(type, from: data)
  }
}

final class CacheTests: XCTestCase {

  // MARK: - InMemoryCache: get / set / delete

  func testMemoryGetSetDelete() async throws {
    let cache = InMemoryCache<String>()

    // Miss before set.
    let missing = try await cache.get("k")
    XCTAssertNil(missing)

    try await cache.set("k", to: "v")
    let hit = try await cache.get("k")
    XCTAssertEqual(hit, "v")

    try await cache.delete("k")
    let afterDelete = try await cache.get("k")
    XCTAssertNil(afterDelete)

    // Deleting a missing key is not an error.
    try await cache.delete("does-not-exist")
  }

  func testMemoryOverwrite() async throws {
    let cache = InMemoryCache<Int>()
    try await cache.set("k", to: 1)
    try await cache.set("k", to: 2)
    let value = try await cache.get("k")
    XCTAssertEqual(value, 2)
  }

  // MARK: - TTL expiry

  func testMemoryTTLExpiry() async throws {
    let clock = TestClock()
    let cache = InMemoryCache<String>(expiry: .seconds(60), now: clock.now)

    try await cache.set("k", to: "v")
    // Still live at +59s.
    clock.advance(59)
    let live = try await cache.get("k")
    XCTAssertEqual(live, "v")

    // Expired at +60s (>= boundary is a miss).
    clock.advance(1)
    let expired = try await cache.get("k")
    XCTAssertNil(expired)
    // The expired entry was purged.
    let count = await cache.count
    XCTAssertEqual(count, 0)
  }

  func testMemoryZeroExpiryNeverExpires() async throws {
    let clock = TestClock()
    let cache = InMemoryCache<String>(expiry: .zero, now: clock.now)
    try await cache.set("k", to: "v")
    clock.advance(60 * 60 * 24 * 365)
    let value = try await cache.get("k")
    XCTAssertEqual(value, "v")
  }

  // MARK: - LRU eviction order

  func testMemoryLRUEvictionOrder() async throws {
    let cache = InMemoryCache<Int>(maxEntries: 2)

    try await cache.set("a", to: 1)
    try await cache.set("b", to: 2)
    // Touch "a" so "b" becomes least-recently-used.
    _ = try await cache.get("a")
    // Insert "c": capacity 2 exceeded, evict LRU "b".
    try await cache.set("c", to: 3)

    let a = try await cache.get("a")
    let b = try await cache.get("b")
    let c = try await cache.get("c")
    XCTAssertEqual(a, 1)
    XCTAssertNil(b, "least-recently-used key should have been evicted")
    XCTAssertEqual(c, 3)
    let count = await cache.count
    XCTAssertEqual(count, 2)
  }

  func testMemoryUnboundedByDefault() async throws {
    let cache = InMemoryCache<Int>()  // maxEntries 0 => unbounded
    for i in 0..<100 { try await cache.set("k\(i)", to: i) }
    let count = await cache.count
    XCTAssertEqual(count, 100)
  }

  // MARK: - Batch ops

  func testMemoryBatch() async throws {
    let cache = InMemoryCache<String>()
    try await cache.setMany(["k1": "one", "k2": "two"])

    let results = try await cache.getMany(["k1", "k2", "missing"])
    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(results["k1"], "one")
    XCTAssertEqual(results["k2"], "two")
    XCTAssertNil(results["missing"])
  }

  func testMemoryPing() async throws {
    let cache = InMemoryCache<String>()
    try await cache.ping()
  }

  // MARK: - DiskCache round-trip

  func testDiskRoundTrip() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = try DiskCache<Widget>(directory: dir)

    let widget = Widget(id: 7, name: "sprocket")
    try await cache.set("w", to: widget)

    let loaded = try await cache.get("w")
    XCTAssertEqual(loaded, widget)

    // Survives a fresh instance over the same directory (real persistence).
    let reopened = try DiskCache<Widget>(directory: dir)
    let persisted = try await reopened.get("w")
    XCTAssertEqual(persisted, widget)

    try await cache.delete("w")
    let afterDelete = try await cache.get("w")
    XCTAssertNil(afterDelete)
  }

  func testDiskKeysWithIllegalPathChars() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = try DiskCache<String>(directory: dir)

    let key = "namespace/with spaces/and:colons"
    try await cache.set(key, to: "ok")
    let value = try await cache.get(key)
    XCTAssertEqual(value, "ok")
  }

  func testDiskBatch() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = try DiskCache<Int>(directory: dir)

    try await cache.setMany(["k1": 1, "k2": 2])
    let results = try await cache.getMany(["k1", "k2", "missing"])
    XCTAssertEqual(results, ["k1": 1, "k2": 2])
  }

  func testDiskTTLExpiry() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    let cache = try DiskCache<String>(directory: dir, expiry: .seconds(30), now: clock.now)

    try await cache.set("k", to: "v")
    clock.advance(29)
    let live = try await cache.get("k")
    XCTAssertEqual(live, "v")

    clock.advance(1)
    let expired = try await cache.get("k")
    XCTAssertNil(expired)
    // The stale file was removed on the expired read.
    let fileURL = dir.appendingPathComponent(
      Data("k".utf8).base64EncodedString().replacingOccurrences(of: "=", with: ""))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
  }

  func testDiskPing() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = try DiskCache<String>(directory: dir)
    try await cache.ping()
  }

  func testDiskUsesInjectedEncoder() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let encoder = CountingEncoder()
    let cache = try DiskCache<String>(directory: dir, encoder: encoder)

    try await cache.set("k", to: "v")
    _ = try await cache.get("k")
    XCTAssertGreaterThan(encoder.encodeCount, 0)
    XCTAssertGreaterThan(encoder.decodeCount, 0)
  }

  // MARK: - NoopCache

  func testNoopCache() async throws {
    let cache = NoopCache<String>()
    try await cache.set("k", to: "v")
    let miss = try await cache.get("k")
    XCTAssertNil(miss)
    let batch = try await cache.getMany(["k"])
    XCTAssertTrue(batch.isEmpty)
    try await cache.setMany(["k": "v"])
    try await cache.delete("k")
    try await cache.ping()
  }

  // MARK: - CacheMock

  func testMockDefaultStoreAndRecording() async throws {
    let mock = CacheMock<String>()
    try await mock.set("k", to: "v")
    let value = try await mock.get("k")
    XCTAssertEqual(value, "v")

    let batch = try await mock.getMany(["k", "missing"])
    XCTAssertEqual(batch, ["k": "v"])

    try await mock.delete("k")
    let afterDelete = try await mock.get("k")
    XCTAssertNil(afterDelete)
    try await mock.ping()

    let setCalls = await mock.setCalls
    let getCalls = await mock.getCalls
    let deleteCalls = await mock.deleteCalls
    let pings = await mock.pingCallCount
    XCTAssertEqual(setCalls.map(\.key), ["k"])
    // Two direct get calls (before and after delete); getMany/delete record separately.
    XCTAssertEqual(getCalls, ["k", "k"])
    XCTAssertEqual(deleteCalls, ["k"])
    XCTAssertEqual(pings, 1)
  }

  func testMockHandlerOverride() async throws {
    let mock = CacheMock<String>()
    await mock.setGetHandler { _ in "scripted" }
    let value = try await mock.get("anything")
    XCTAssertEqual(value, "scripted")

    struct Boom: Error {}
    await mock.setPingHandler { throw Boom() }
    do {
      try await mock.ping()
      XCTFail("expected ping to throw")
    } catch is Boom {
      // expected
    }
  }

  // MARK: - Config: lenient decode

  func testConfigEmptyObjectDecodes() throws {
    let cfg = try JSONDecoder().decode(CacheConfig.self, from: Data("{}".utf8))
    XCTAssertEqual(cfg.provider, "")
    XCTAssertEqual(cfg.expiry, .zero)
    XCTAssertEqual(cfg.maxEntries, 0)
    XCTAssertNil(cfg.directory)
    // Zero expiry resolves to one hour, mirroring Go's fallback.
    XCTAssertEqual(cfg.resolvedExpiry, .seconds(3600))
  }

  func testConfigPartialDecode() throws {
    let json = #"{"provider":"disk","maxEntries":50}"#
    let cfg = try JSONDecoder().decode(CacheConfig.self, from: Data(json.utf8))
    XCTAssertEqual(cfg.provider, "disk")
    XCTAssertEqual(cfg.maxEntries, 50)
    XCTAssertEqual(cfg.expiry, .zero)
  }

  func testConfigExpiryNanosecondsRoundTrip() throws {
    // 1h == 3_600_000_000_000 ns on the wire (Go's time.Duration JSON shape).
    let json = #"{"expiry":3600000000000}"#
    let cfg = try JSONDecoder().decode(CacheConfig.self, from: Data(json.utf8))
    XCTAssertEqual(cfg.expiry, .seconds(3600))

    let reencoded = try JSONEncoder().encode(cfg)
    let roundTripped = try JSONDecoder().decode(CacheConfig.self, from: reencoded)
    XCTAssertEqual(roundTripped, cfg)
  }

  // MARK: - Config: factory (provider seam)

  func testMakeCacheMemory() async throws {
    let cfg = CacheConfig(provider: "memory")
    let cache: any BatchCache<String> = try cfg.makeCache(pillars: .noop)
    try await cache.set("k", to: "v")
    let value = try await cache.get("k")
    XCTAssertEqual(value, "v")
  }

  func testMakeCacheDefaultProviderIsMemory() throws {
    let cfg = CacheConfig()  // empty provider
    let cache: any BatchCache<String> = try cfg.makeCache(pillars: .noop)
    XCTAssertNotNil(cache)
  }

  func testMakeCacheDisk() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cfg = CacheConfig(provider: "disk", directory: dir.path)
    let cache: any BatchCache<Widget> = try cfg.makeCache(pillars: .noop)
    let widget = Widget(id: 1, name: "a")
    try await cache.set("w", to: widget)
    let loaded = try await cache.get("w")
    XCTAssertEqual(loaded, widget)
  }

  func testMakeCacheInvalidProviderThrows() throws {
    let cfg = CacheConfig(provider: "redis")
    XCTAssertThrowsError(
      try cfg.makeCache(pillars: .noop) as any BatchCache<String>
    ) { error in
      XCTAssertEqual(error as? CacheError, .invalidProvider("redis"))
    }
  }

  // MARK: - Helpers

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("cache-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
