import Foundation
import Testing

@testable import RateLimiting

@Suite("RateLimitingConfig.ensureDefaults")
struct RateLimitingConfigDefaultsTests {
  @Test("fills defaults for an empty config")
  func fillsDefaults() {
    var cfg = RateLimitingConfig()
    cfg.ensureDefaults()

    #expect(cfg.requestsPerSecond == 10.0)
    #expect(cfg.burstSize == 20)
  }

  @Test("preserves already-set values")
  func preservesSet() {
    var cfg = RateLimitingConfig(requestsPerSecond: 5, burstSize: 10)
    cfg.ensureDefaults()

    #expect(cfg.requestsPerSecond == 5)
    #expect(cfg.burstSize == 10)
  }

  @Test("ensuringDefaults returns a defaulted copy without mutating the original")
  func nonMutating() {
    let original = RateLimitingConfig()
    let defaulted = original.ensuringDefaults()

    #expect(original.requestsPerSecond == 0)
    #expect(defaulted.requestsPerSecond == 10.0)
  }
}

@Suite("RateLimitingConfig.validate")
struct RateLimitingConfigValidateTests {
  @Test("accepts a valid config")
  func acceptsValid() throws {
    try RateLimitingConfig(requestsPerSecond: 1, burstSize: 1).validate()
  }

  @Test("rejects a negative requestsPerSecond")
  func rejectsNegativeRate() {
    #expect(throws: RateLimitingError.invalidRequestsPerSecond(-1)) {
      try RateLimitingConfig(requestsPerSecond: -1, burstSize: 1).validate()
    }
  }

  @Test("rejects a negative burstSize")
  func rejectsNegativeBurst() {
    #expect(throws: RateLimitingError.invalidBurstSize(-1)) {
      try RateLimitingConfig(requestsPerSecond: 1, burstSize: -1).validate()
    }
  }
}

@Suite("RateLimitingConfig Codable")
struct RateLimitingConfigCodableTests {
  @Test("encodes with Go's JSON keys")
  func encodesGoKeys() throws {
    let cfg = RateLimitingConfig(provider: "memory", requestsPerSecond: 5, burstSize: 10)

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["provider"] as? String == "memory")
    #expect(json["requestsPerSecond"] as? Double == 5)
    #expect(json["burstSize"] as? Int == 10)
  }

  @Test("decodes a config authored for a Go peer")
  func decodesGoWireShape() throws {
    let json = Data(
      #"{"provider":"memory","requestsPerSecond":5,"burstSize":10}"#.utf8)
    let cfg = try JSONDecoder().decode(RateLimitingConfig.self, from: json)

    #expect(cfg.provider == "memory")
    #expect(cfg.requestsPerSecond == 5)
    #expect(cfg.burstSize == 10)
  }

  @Test("missing fields decode to zero so ensureDefaults can fill them")
  func partialDecode() throws {
    let cfg = try JSONDecoder().decode(RateLimitingConfig.self, from: Data("{}".utf8))

    #expect(cfg.provider == "")
    #expect(cfg.requestsPerSecond == 0)
    #expect(cfg.burstSize == 0)
    #expect(cfg.ensuringDefaults().requestsPerSecond == 10.0)
    #expect(cfg.ensuringDefaults().burstSize == 20)
  }

  @Test("a Go payload carrying the dropped redis sub-config still decodes")
  func ignoresDroppedRedisConfig() throws {
    let json = Data(
      #"{"provider":"redis","redis":{"addresses":["127.0.0.1:6379"]},"requestsPerSecond":1,"burstSize":1}"#
        .utf8)
    let cfg = try JSONDecoder().decode(RateLimitingConfig.self, from: json)

    #expect(cfg.provider == "redis")
    #expect(cfg.requestsPerSecond == 1)
  }

  @Test("round-trips through JSON")
  func roundTrips() throws {
    let original = RateLimitingConfig(provider: "memory", requestsPerSecond: 42.5, burstSize: 7)
    let decoded = try JSONDecoder().decode(
      RateLimitingConfig.self, from: try JSONEncoder().encode(original))

    #expect(decoded == original)
  }
}

@Suite("RateLimitingConfig.provideRateLimiter")
struct RateLimitingConfigProvideTests {
  @Test("nil-equivalent (empty) provider returns noop")
  func emptyProviderReturnsNoop() async throws {
    let limiter = try RateLimitingConfig(provider: "").provideRateLimiter()
    #expect(limiter is NoopRateLimiter)
    #expect(await limiter.allow(key: "x"))
  }

  @Test("\"noop\" provider returns noop")
  func noopProviderReturnsNoop() throws {
    let limiter = try RateLimitingConfig(provider: RateLimitingConfig.providerNoop)
      .provideRateLimiter()
    #expect(limiter is NoopRateLimiter)
  }

  @Test("\"memory\" provider returns a token-bucket limiter honoring burst")
  func memoryProviderReturnsTokenBucket() async throws {
    let limiter = try RateLimitingConfig(
      provider: RateLimitingConfig.providerMemory, requestsPerSecond: 1, burstSize: 1
    ).provideRateLimiter()

    #expect(limiter is TokenBucketRateLimiter<ContinuousClock>)
    #expect(await limiter.allow(key: "x"))
    #expect(await !limiter.allow(key: "x"))
  }

  @Test("unknown provider throws, matching Go's error switch default")
  func unknownProviderThrows() {
    #expect(throws: RateLimitingError.unknownProvider("bogus")) {
      try RateLimitingConfig(provider: "bogus").provideRateLimiter()
    }
  }

  @Test("dropped \"redis\" provider throws as unknown, since the backend no longer exists")
  func redisProviderThrows() {
    #expect(throws: RateLimitingError.unknownProvider("redis")) {
      try RateLimitingConfig(provider: "redis").provideRateLimiter()
    }
  }

  @Test("provider matching is case-insensitive and trims whitespace, matching Go's normalization")
  func providerIsNormalized() throws {
    let limiter = try RateLimitingConfig(provider: "  MEMORY  ").provideRateLimiter()
    #expect(limiter is TokenBucketRateLimiter<ContinuousClock>)
  }
}
