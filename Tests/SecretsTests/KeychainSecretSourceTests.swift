import Foundation
import Observability
import Security
import Testing

@testable import Secrets

/// Exercises ``KeychainSecretSource`` against the real Keychain (there is no in-memory substitute for
/// `SecItemCopyMatching`). Every test uses its own unique `kSecAttrAccount` (and, where relevant, a
/// dedicated `kSecAttrService`) so parallel `swift-testing` cases never collide, and cleans up whatever
/// it wrote before returning.
@Suite("KeychainSecretSource")
struct KeychainSecretSourceTests {
  private static let service = "platform-swift.secrets.tests"

  /// Writes a generic-password item directly via `SecItemAdd`, bypassing the module under test, so a
  /// "the item already exists" assertion is independent of ``KeychainSecretSource`` having any way to
  /// write one itself (its seam, matching Go's `SecretSource`, is read/close only).
  private func seed(account: String, value: Data) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
      kSecValueData as String: value,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    #expect(status == errSecSuccess)
  }

  private func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }

  @Test("returns the value for an existing item")
  func returnsExistingValue() async throws {
    let account = "existing-\(UUID().uuidString)"
    seed(account: account, value: Data("s3cret".utf8))
    defer { delete(account: account) }

    let source = KeychainSecretSource(service: Self.service)
    let got = try await source.getSecret(name: account)
    #expect(got == "s3cret")
  }

  @Test("throws notFound for a name with no matching item")
  func throwsNotFoundWhenMissing() async {
    let account = "missing-\(UUID().uuidString)"
    let source = KeychainSecretSource(service: Self.service)

    await #expect(throws: SecretsError.notFound(account)) {
      try await source.getSecret(name: account)
    }
  }

  @Test("returns an empty string, not an error, for an item that legitimately stores no data")
  func returnsEmptyForLegitimatelyEmptyItem() async throws {
    let account = "empty-\(UUID().uuidString)"
    seed(account: account, value: Data())
    defer { delete(account: account) }

    let source = KeychainSecretSource(service: Self.service)
    let got = try await source.getSecret(name: account)
    #expect(got == "")
  }

  @Test("a different service never sees another service's item")
  func serviceScopesLookup() async {
    let account = "scoped-\(UUID().uuidString)"
    seed(account: account, value: Data("s3cret".utf8))
    defer { delete(account: account) }

    let source = KeychainSecretSource(service: "platform-swift.secrets.tests.other-service")
    await #expect(throws: SecretsError.notFound(account)) {
      try await source.getSecret(name: account)
    }
  }

  @Test("only the lookup key is observed, never the secret's value")
  func observesOnlyTheLookupKey() async throws {
    let account = "observed-\(UUID().uuidString)"
    seed(account: account, value: Data("super-secret".utf8))
    defer { delete(account: account) }

    let observer = recordingObserver("test")
    let source = KeychainSecretSource(service: Self.service, observer: observer)

    _ = try await source.getSecret(name: account)

    let op = observer.operations.first!
    #expect(op.value(forKey: "secret_key") == account)
    #expect(!op.observations.contains { $0.value == "super-secret" })
  }

  @Test("close is a no-op")
  func closeIsNoop() async {
    let source = KeychainSecretSource(service: Self.service)
    await source.close()
  }

  @Test("the Pillars convenience initializer builds a usable source")
  func pillarsConvenienceInitializer() async {
    let account = "pillars-\(UUID().uuidString)"
    let source = KeychainSecretSource(service: Self.service, pillars: .noop)

    await #expect(throws: SecretsError.notFound(account)) {
      try await source.getSecret(name: account)
    }
  }
}
