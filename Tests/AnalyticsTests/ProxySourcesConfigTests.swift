import Foundation
import Testing

@testable import Analytics

@Suite("ProxySourcesConfig")
struct ProxySourcesConfigTests {
  @Test("toMap skips nil entries")
  func toMapSkipsNil() {
    let config = ProxySourcesConfig(ios: SourceConfig(provider: "segment"), web: nil)
    #expect(Set(config.toMap().keys) == ["ios"])
  }

  @Test("toMap includes every configured entry, keyed by source name")
  func toMapIncludesBoth() {
    let config = ProxySourcesConfig(
      ios: SourceConfig(provider: "segment"), web: SourceConfig(provider: "posthog"))
    let map = config.toMap()

    #expect(map["ios"]?.provider == "segment")
    #expect(map["web"]?.provider == "posthog")
  }

  @Test("toMap is empty when no sources are configured")
  func toMapEmpty() {
    #expect(ProxySourcesConfig().toMap().isEmpty)
  }

  @Test("ensureDefaults fills defaults on every configured source, leaving nils alone")
  func ensureDefaults() {
    var config = ProxySourcesConfig(ios: SourceConfig(provider: "segment"), web: nil)
    config.ensureDefaults()

    #expect(config.ios?.circuitBreaker.name == "UNKNOWN")
    #expect(config.web == nil)
  }

  @Test("decodes the Go JSON shape (\"ios\"/\"web\" keys)")
  func decodesGoShape() throws {
    let json = Data(#"{"ios":{"provider":"segment"},"web":null}"#.utf8)
    let config = try JSONDecoder().decode(ProxySourcesConfig.self, from: json)

    #expect(config.ios?.provider == "segment")
    #expect(config.web == nil)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = ProxySourcesConfig(ios: SourceConfig(provider: "segment"))
    let decoded = try JSONDecoder().decode(
      ProxySourcesConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
