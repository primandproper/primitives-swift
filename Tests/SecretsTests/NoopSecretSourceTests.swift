import Testing

@testable import Secrets

@Suite("NoopSecretSource")
struct NoopSecretSourceTests {
  @Test("getSecret returns an empty string for any name, and never throws")
  func getSecretReturnsEmpty() async throws {
    let source = NoopSecretSource()
    let got = try await source.getSecret(name: "any-key")
    #expect(got == "")
  }

  @Test("close is a no-op")
  func closeIsNoop() async {
    let source = NoopSecretSource()
    await source.close()
  }
}
