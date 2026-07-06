import Testing

@testable import Secrets

@Suite("SecretSourceMock")
struct SecretSourceMockTests {
  @Test("an unset handler defaults to an empty string and never throws")
  func defaultsToEmpty() async throws {
    let mock = SecretSourceMock()
    let got = try await mock.getSecret(name: "any-key")
    #expect(got == "")
    let calls = await mock.getSecretCalls
    #expect(calls == [SecretSourceMock.GetSecretCall(name: "any-key")])
  }

  @Test("getSecretHandler drives the return value and can throw")
  func handlerDrivesResult() async throws {
    let mock = SecretSourceMock(
      getSecretHandler: { name in
        if name == "missing" { throw SecretsError.notFound(name) }
        return "value-for-\(name)"
      })

    let got = try await mock.getSecret(name: "present")
    #expect(got == "value-for-present")

    await #expect(throws: SecretsError.notFound("missing")) {
      try await mock.getSecret(name: "missing")
    }
  }

  @Test("close records a call and drives closeHandler")
  func closeRecordsAndDrivesHandler() async {
    let flag = Flag()
    let mock = SecretSourceMock(closeHandler: { await flag.set() })

    await mock.close()

    #expect(await mock.closeCallCount == 1)
    #expect(await flag.value)
  }
}

private actor Flag {
  private(set) var value = false
  func set() { value = true }
}
