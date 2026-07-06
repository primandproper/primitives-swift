import Foundation
import Observability
import Testing

@testable import Secrets

@Suite("SecretsConfig")
struct SecretsConfigTests {
  @Test("an empty JSON object decodes to the Go zero value for every field")
  func emptyObjectDecodesToZeroValue() throws {
    let cfg = try JSONDecoder().decode(SecretsConfig.self, from: Data("{}".utf8))
    #expect(cfg == SecretsConfig())
    #expect(cfg.provider == "")
    #expect(cfg.keychain.service == "")
    #expect(cfg.keychain.accessGroup == nil)
  }

  @Test("a partial JSON payload fills in the zero value for whatever's missing")
  func partialObjectDecodesLeniently() throws {
    let cfg = try JSONDecoder().decode(
      SecretsConfig.self, from: Data(#"{"provider":"environment"}"#.utf8))
    #expect(cfg.provider == "environment")
    #expect(cfg.keychain == SecretsConfig.KeychainConfig())
  }

  @Test("a nested keychain object decodes leniently too")
  func nestedKeychainObjectDecodesLeniently() throws {
    let cfg = try JSONDecoder().decode(
      SecretsConfig.self, from: Data(#"{"provider":"keychain","keychain":{}}"#.utf8))
    #expect(cfg.keychain.service == "")
    #expect(cfg.keychain.accessGroup == nil)
  }

  @Test("round-trips through encode/decode")
  func roundTrips() throws {
    let cfg = SecretsConfig(
      provider: "keychain",
      keychain: .init(service: "com.example.app", accessGroup: "TEAMID.shared"))
    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(SecretsConfig.self, from: data)
    #expect(decoded == cfg)
  }

  @Test("an empty provider resolves to KeychainSecretSource")
  func emptyProviderResolvesToKeychain() throws {
    let source = try SecretsConfig().makeSecretSource(pillars: .noop)
    #expect(source is KeychainSecretSource)
  }

  @Test("\"keychain\" resolves to KeychainSecretSource, using the configured service")
  func keychainProviderResolvesToKeychain() throws {
    let cfg = SecretsConfig(
      provider: SecretsConfig.providerKeychain, keychain: .init(service: "com.example.app"))
    let source = try cfg.makeSecretSource(pillars: .noop)
    #expect(source is KeychainSecretSource)
  }

  @Test("resolution is lenient about surrounding whitespace and case")
  func resolutionIsLenient() throws {
    let cfg = SecretsConfig(provider: "  ENVIRONMENT  ")
    let source = try cfg.makeSecretSource(pillars: .noop)
    #expect(source is EnvironmentSecretSource)
  }

  @Test("\"environment\" resolves to EnvironmentSecretSource")
  func environmentProviderResolvesToEnvironment() throws {
    let cfg = SecretsConfig(provider: SecretsConfig.providerEnvironment)
    let source = try cfg.makeSecretSource(pillars: .noop)
    #expect(source is EnvironmentSecretSource)
  }

  @Test("\"noop\" resolves to NoopSecretSource")
  func noopProviderResolvesToNoop() throws {
    let cfg = SecretsConfig(provider: SecretsConfig.providerNoop)
    let source = try cfg.makeSecretSource(pillars: .noop)
    #expect(source is NoopSecretSource)
  }

  @Test(
    "gcp/ssm/kubectl are recognized but unsupported",
    arguments: [
      SecretsConfig.providerGCP, SecretsConfig.providerSSM, SecretsConfig.providerKubectl,
    ]
  )
  func droppedCloudProvidersAreUnsupported(provider: String) {
    let cfg = SecretsConfig(provider: provider)
    #expect(throws: SecretsError.unsupportedProvider(provider)) {
      try cfg.makeSecretSource(pillars: .noop)
    }
  }

  @Test("an unrecognized provider throws unsupportedProvider")
  func unknownProviderThrows() {
    let cfg = SecretsConfig(provider: "vault")
    #expect(throws: SecretsError.unsupportedProvider("vault")) {
      try cfg.makeSecretSource(pillars: .noop)
    }
  }

  @Test("an empty configured service name falls back to the supplied bundle identifier")
  func emptyServiceFallsBackToBundleIdentifier() throws {
    let cfg = SecretsConfig(provider: SecretsConfig.providerKeychain)
    let source = try cfg.makeSecretSource(pillars: .noop, bundleIdentifier: "com.example.fallback")
    #expect(source is KeychainSecretSource)
  }
}
