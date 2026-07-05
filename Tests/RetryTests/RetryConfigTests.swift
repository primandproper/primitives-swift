import Foundation
import Testing

@testable import Retry

@Suite("RetryConfig.ensureDefaults")
struct RetryConfigEnsureDefaultsTests {
  @Test("sets defaults for zero values")
  func setsDefaults() {
    var cfg = RetryConfig()
    cfg.ensureDefaults()

    #expect(cfg.maxAttempts == 3)
    #expect(cfg.initialDelay == .milliseconds(100))
    #expect(cfg.maxDelay == .seconds(5))
    #expect(cfg.multiplier == 2.0)
  }

  @Test("preserves non-zero values")
  func preservesNonZero() {
    var cfg = RetryConfig(
      maxAttempts: 7, initialDelay: .seconds(1), maxDelay: .seconds(10), multiplier: 3.0)
    cfg.ensureDefaults()

    #expect(cfg.maxAttempts == 7)
    #expect(cfg.initialDelay == .seconds(1))
    #expect(cfg.maxDelay == .seconds(10))
    #expect(cfg.multiplier == 3.0)
  }

  @Test("clamps invalid values: negative delays and a sub-1 multiplier")
  func clampsInvalid() {
    // A multiplier below 1 shrinks the backoff and negative delays are nonsensical; because the
    // constructor can't reject them, ensureDefaults must replace them.
    var cfg = RetryConfig(
      maxAttempts: 2, initialDelay: .seconds(-1), maxDelay: .seconds(-1), multiplier: 0.5)
    cfg.ensureDefaults()

    #expect(cfg.maxAttempts == 2)
    #expect(cfg.initialDelay == .milliseconds(100))
    #expect(cfg.maxDelay == .seconds(5))
    #expect(cfg.multiplier == 2.0)
  }

  @Test("ensuringDefaults returns a defaulted copy without mutating the original")
  func ensuringDefaultsIsNonMutating() {
    let original = RetryConfig()
    let defaulted = original.ensuringDefaults()

    #expect(original.maxAttempts == 0)
    #expect(defaulted.maxAttempts == 3)
  }
}

@Suite("RetryConfig Codable")
struct RetryConfigCodableTests {
  @Test("durations encode as integer nanoseconds, matching Go's time.Duration JSON")
  func encodesNanoseconds() throws {
    let cfg = RetryConfig(
      maxAttempts: 3, initialDelay: .milliseconds(100), maxDelay: .seconds(5), multiplier: 2.0,
      useJitter: true)

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["maxAttempts"] as? Int == 3)
    #expect(json["initialDelay"] as? Int == 100_000_000)  // 100ms in ns
    #expect(json["maxDelay"] as? Int == 5_000_000_000)  // 5s in ns
    #expect(json["multiplier"] as? Double == 2.0)
    #expect(json["useJitter"] as? Bool == true)
  }

  @Test("round-trips through JSON")
  func roundTrips() throws {
    let original = RetryConfig(
      maxAttempts: 4, initialDelay: .milliseconds(250), maxDelay: .seconds(30), multiplier: 1.5,
      useJitter: true)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RetryConfig.self, from: data)

    #expect(decoded == original)
  }

  @Test("decodes an integer-nanosecond duration written by a Go peer")
  func decodesGoWireShape() throws {
    let json = Data(
      #"{"maxAttempts":3,"initialDelay":100000000,"maxDelay":5000000000,"multiplier":2,"useJitter":false}"#
        .utf8)
    let cfg = try JSONDecoder().decode(RetryConfig.self, from: json)

    #expect(cfg.initialDelay == .milliseconds(100))
    #expect(cfg.maxDelay == .seconds(5))
  }

  @Test("missing fields decode to zero so ensureDefaults can fill them")
  func partialDecode() throws {
    let cfg = try JSONDecoder().decode(RetryConfig.self, from: Data("{}".utf8))

    #expect(cfg.maxAttempts == 0)
    #expect(cfg.initialDelay == .zero)
    #expect(cfg.ensuringDefaults().maxAttempts == 3)
  }
}
