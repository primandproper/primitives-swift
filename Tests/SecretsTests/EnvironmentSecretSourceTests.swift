import Observability
import Testing

@testable import Secrets

@Suite("EnvironmentSecretSource")
struct EnvironmentSecretSourceTests {
  @Test("returns the value for a name present in the injected environment")
  func returnsEnvironmentValue() async throws {
    let source = EnvironmentSecretSource(
      environment: ["API_KEY": "secret-value"], infoDictionary: [:])
    let got = try await source.getSecret(name: "API_KEY")
    #expect(got == "secret-value")
  }

  @Test("falls back to the Info.plist-style dictionary when absent from the environment")
  func fallsBackToInfoDictionary() async throws {
    let source = EnvironmentSecretSource(
      environment: [:], infoDictionary: ["APIKey": "plist-value"])
    let got = try await source.getSecret(name: "APIKey")
    #expect(got == "plist-value")
  }

  @Test("the environment takes precedence over the Info.plist fallback")
  func environmentTakesPrecedence() async throws {
    let source = EnvironmentSecretSource(
      environment: ["KEY": "from-env"], infoDictionary: ["KEY": "from-plist"])
    let got = try await source.getSecret(name: "KEY")
    #expect(got == "from-env")
  }

  @Test("throws notFound for a name absent from both sources")
  func throwsNotFoundWhenAbsent() async {
    let source = EnvironmentSecretSource(environment: [:], infoDictionary: [:])
    await #expect(throws: SecretsError.notFound("MISSING")) {
      try await source.getSecret(name: "MISSING")
    }
  }

  @Test("returns an empty string, not an error, for a name set to an empty value")
  func returnsEmptyForSetButEmptyValue() async throws {
    let source = EnvironmentSecretSource(environment: ["EMPTY": ""], infoDictionary: [:])
    let got = try await source.getSecret(name: "EMPTY")
    #expect(got == "")
  }

  @Test("a non-String Info.plist entry is ignored rather than crashing")
  func ignoresNonStringInfoDictionaryEntry() async {
    let source = EnvironmentSecretSource(environment: [:], infoDictionary: ["FLAG": true])
    await #expect(throws: SecretsError.notFound("FLAG")) {
      try await source.getSecret(name: "FLAG")
    }
  }

  @Test("only the lookup key is observed, never the secret's value")
  func observesOnlyTheLookupKey() async throws {
    let observer = recordingObserver("test")
    let source = EnvironmentSecretSource(
      environment: ["API_KEY": "super-secret"], infoDictionary: [:], observer: observer)

    _ = try await source.getSecret(name: "API_KEY")

    let op = observer.operations.first!
    #expect(op.value(forKey: "secret_key") == "API_KEY")
    #expect(!op.observations.contains { $0.value == "super-secret" })
  }

  @Test("close is a no-op")
  func closeIsNoop() async {
    let source = EnvironmentSecretSource(environment: [:], infoDictionary: [:])
    await source.close()
  }
}
