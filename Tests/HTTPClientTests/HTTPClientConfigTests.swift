import Foundation
import Testing

@testable import HTTPClient

@Suite("HTTPClientConfig")
struct HTTPClientConfigTests {
  @Test("ensureDefaults fills zero fields, mirroring Go's EnsureDefaults")
  func ensureDefaultsFillsZeros() {
    var cfg = HTTPClientConfig()
    cfg.ensureDefaults()
    #expect(cfg.timeout == .seconds(10))
    #expect(cfg.maxIdleConns == 100)
    #expect(cfg.maxIdleConnsPerHost == 100)
  }

  @Test("ensureDefaults preserves non-zero values")
  func ensureDefaultsPreservesValues() {
    var cfg = HTTPClientConfig(
      timeout: .seconds(5), maxIdleConns: 50, maxIdleConnsPerHost: 25)
    cfg.ensureDefaults()
    #expect(cfg.timeout == .seconds(5))
    #expect(cfg.maxIdleConns == 50)
    #expect(cfg.maxIdleConnsPerHost == 25)
  }

  @Test("validate accepts a sound config")
  func validateAcceptsValid() throws {
    let cfg = HTTPClientConfig(
      timeout: .seconds(1), maxIdleConns: 10, maxIdleConnsPerHost: 5)
    try cfg.validate()
  }

  @Test("validate rejects a sub-millisecond timeout")
  func validateRejectsTimeout() {
    let cfg = HTTPClientConfig(timeout: .zero, maxIdleConns: 10, maxIdleConnsPerHost: 5)
    #expect(throws: HTTPClientError.self) { try cfg.validate() }
  }

  @Test("validate rejects zero connection caps")
  func validateRejectsConnCaps() {
    let noConns = HTTPClientConfig(timeout: .seconds(1), maxIdleConns: 0, maxIdleConnsPerHost: 5)
    #expect(throws: HTTPClientError.self) { try noConns.validate() }

    let noPerHost = HTTPClientConfig(timeout: .seconds(1), maxIdleConns: 10, maxIdleConnsPerHost: 0)
    #expect(throws: HTTPClientError.self) { try noPerHost.validate() }
  }

  @Test("timeout encodes to integer nanoseconds, round-tripping with a Go time.Duration")
  func codableNanosecondContract() throws {
    let cfg = HTTPClientConfig(
      timeout: .seconds(2), maxIdleConns: 42, maxIdleConnsPerHost: 21, enableTracing: true)

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect((json["timeout"] as? NSNumber)?.int64Value == 2_000_000_000)
    #expect((json["maxIdleConns"] as? NSNumber)?.intValue == 42)
    #expect((json["maxIdleConnsPerHost"] as? NSNumber)?.intValue == 21)
    #expect((json["enableTracing"] as? NSNumber)?.boolValue == true)

    let decoded = try JSONDecoder().decode(HTTPClientConfig.self, from: data)
    #expect(decoded == cfg)
  }

  @Test("a partial JSON object decodes missing fields to zero for ensureDefaults to fill")
  func partialJSONDecodesToZero() throws {
    let data = Data(#"{"timeout": 3000000000}"#.utf8)
    let decoded = try JSONDecoder().decode(HTTPClientConfig.self, from: data)
    #expect(decoded.timeout == .seconds(3))
    #expect(decoded.maxIdleConns == 0)
    #expect(decoded.maxIdleConnsPerHost == 0)

    let defaulted = decoded.ensuringDefaults()
    #expect(defaulted.maxIdleConns == 100)
    #expect(defaulted.maxIdleConnsPerHost == 100)
  }

  @Test("buildSessionConfiguration maps timeout and per-host cap onto URLSession")
  func buildSessionConfigurationMapping() {
    let cfg = HTTPClientConfig(
      timeout: .seconds(4), maxIdleConns: 100, maxIdleConnsPerHost: 7)
    let sessionConfig = cfg.buildSessionConfiguration()
    #expect(sessionConfig.timeoutIntervalForRequest == 4)
    #expect(sessionConfig.httpMaximumConnectionsPerHost == 7)
  }
}
