import Foundation
import Testing

@testable import CircuitBreaking

@Suite("CircuitBreakerConfig.ensureDefaults")
struct CircuitBreakerConfigDefaultsTests {
  @Test("fills defaults for an empty config")
  func fillsDefaults() {
    var cfg = CircuitBreakerConfig()
    cfg.ensureDefaults()

    #expect(cfg.name == "UNKNOWN")
    #expect(cfg.errorRate == 100)
    #expect(cfg.minimumSampleThreshold == 20)
  }

  @Test("preserves already-set values")
  func preservesSet() {
    var cfg = CircuitBreakerConfig(name: "svc", errorRate: 50, minimumSampleThreshold: 500)
    cfg.ensureDefaults()

    #expect(cfg.name == "svc")
    #expect(cfg.errorRate == 50)
    #expect(cfg.minimumSampleThreshold == 500)
  }

  @Test("ensuringDefaults returns a defaulted copy without mutating the original")
  func nonMutating() {
    let original = CircuitBreakerConfig()
    let defaulted = original.ensuringDefaults()

    #expect(original.name == "")
    #expect(defaulted.name == "UNKNOWN")
  }
}

@Suite("CircuitBreakerConfig.validate")
struct CircuitBreakerConfigValidateTests {
  @Test("accepts a valid config")
  func acceptsValid() throws {
    try CircuitBreakerConfig(name: "svc", errorRate: 99, minimumSampleThreshold: 123).validate()
  }

  @Test("rejects a missing name")
  func rejectsMissingName() {
    #expect(throws: CircuitBreakerConfigError.missingName) {
      try CircuitBreakerConfig(name: "", errorRate: 99).validate()
    }
  }

  @Test("rejects an error rate above 100")
  func rejectsOutOfRange() {
    #expect(throws: CircuitBreakerConfigError.errorRateOutOfRange(200)) {
      try CircuitBreakerConfig(name: "svc", errorRate: 200).validate()
    }
  }
}

@Suite("CircuitBreakerConfig Codable")
struct CircuitBreakerConfigCodableTests {
  @Test("encodes with Go's JSON keys")
  func encodesGoKeys() throws {
    let cfg = CircuitBreakerConfig(name: "svc", errorRate: 50, minimumSampleThreshold: 5)

    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["name"] as? String == "svc")
    #expect(json["circuitBreakerErrorPercentage"] as? Double == 50)
    #expect(json["circuitBreakerMinimumOccurrenceThreshold"] as? Int == 5)
  }

  @Test("decodes a config authored for a Go peer")
  func decodesGoWireShape() throws {
    let json = Data(
      #"{"name":"svc","circuitBreakerErrorPercentage":50,"circuitBreakerMinimumOccurrenceThreshold":5}"#
        .utf8)
    let cfg = try JSONDecoder().decode(CircuitBreakerConfig.self, from: json)

    #expect(cfg.name == "svc")
    #expect(cfg.errorRate == 50)
    #expect(cfg.minimumSampleThreshold == 5)
  }

  @Test("missing fields decode to zero so ensureDefaults can fill them")
  func partialDecode() throws {
    let cfg = try JSONDecoder().decode(CircuitBreakerConfig.self, from: Data("{}".utf8))

    #expect(cfg.name == "")
    #expect(cfg.errorRate == 0)
    #expect(cfg.minimumSampleThreshold == 0)
    #expect(cfg.ensuringDefaults().name == "UNKNOWN")
  }

  @Test("round-trips through JSON")
  func roundTrips() throws {
    let original = CircuitBreakerConfig(name: "svc", errorRate: 42.5, minimumSampleThreshold: 7)
    let decoded = try JSONDecoder().decode(
      CircuitBreakerConfig.self, from: try JSONEncoder().encode(original))

    #expect(decoded == original)
  }
}

@Suite("CircuitBreakerConfig.provideCircuitBreaker")
struct CircuitBreakerConfigProvideTests {
  @Test("an unset name still yields a real breaker (defaults applied before validation)")
  func unsetNameYieldsReal() {
    let cb = CircuitBreakerConfig(name: "").provideCircuitBreaker()
    #expect(cb is StandardCircuitBreaker)
  }

  @Test("an out-of-range error rate degrades to a noop breaker")
  func invalidYieldsNoop() {
    let cb = CircuitBreakerConfig(name: "svc", errorRate: 200).provideCircuitBreaker()
    #expect(cb is NoopCircuitBreaker)
  }
}

@Suite("KeyedCircuitBreakerConfig")
struct KeyedCircuitBreakerConfigTests {
  @Test("ensureDefaults delegates to the base config")
  func ensureDefaultsDelegates() {
    var cfg = KeyedCircuitBreakerConfig()
    cfg.ensureDefaults()

    #expect(cfg.base.name == "UNKNOWN")
    #expect(cfg.base.errorRate == 100)
    #expect(cfg.base.minimumSampleThreshold == 20)
  }

  @Test("validate rejects an empty key")
  func rejectsEmptyKey() {
    let cfg = KeyedCircuitBreakerConfig(keys: ["123", ""], base: .init(name: "kb"))
    #expect(throws: KeyedCircuitBreakerConfigError.emptyKey) {
      try cfg.validate()
    }
  }

  @Test("uses Go's JSON keys")
  func codableKeys() throws {
    let cfg = KeyedCircuitBreakerConfig(keys: ["a", "b"], base: .init(name: "kb"))
    let data = try JSONEncoder().encode(cfg)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["circuitBreakerKeys"] as? [String] == ["a", "b"])
    #expect(json["base"] != nil)
  }

  @Test("provides a partitioned breaker: registered keys get dedicated breakers, others share global")
  func providesPartitioned() {
    let cfg = KeyedCircuitBreakerConfig(keys: ["123"], base: .init(name: "kb"))
    let keyed = cfg.provideKeyedCircuitBreaker()

    #expect(keyed is PartitionedCircuitBreaker)

    let dedicated = keyed.breaker(for: "123") as? StandardCircuitBreaker
    let globalA = keyed.breaker(for: "456") as? StandardCircuitBreaker
    let globalB = keyed.breaker(for: "789") as? StandardCircuitBreaker

    #expect(dedicated !== globalA)  // a registered key gets its own breaker
    #expect(globalA === globalB)  // unregistered keys share the global one
  }

  @Test("an invalid base config degrades to a noop keyed breaker")
  func invalidYieldsNoop() {
    let cfg = KeyedCircuitBreakerConfig(keys: [], base: .init(name: "", errorRate: 200))
    let keyed = cfg.provideKeyedCircuitBreaker()
    #expect(keyed is NoopKeyedCircuitBreaker)
  }
}
