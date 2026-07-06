/// A test double for ``SecretSource``, ported from platform-go's moq-generated
/// `secretsmock.SecretSourceMock` idiom (this package doesn't ship one, but ``Analytics/EventReporterMock``
/// and ``LLM/LLMProviderMock`` establish the pattern this port applies uniformly).
///
/// An unset handler is a quiet no-op default: ``getSecret(name:)`` returns `""` (never
/// ``SecretsError/notFound(_:)``) and ``close()`` does nothing, so a test can construct a bare
/// `SecretSourceMock()` without configuring every method it doesn't care about.
///
/// The handler closures are `let`, injected once at ``init``: under Swift 6 actor isolation a
/// `public var` on an actor can't be assigned from another isolation domain, so configuration happens at
/// construction time (REPO-05).
public actor SecretSourceMock: SecretSource {
  public struct GetSecretCall: Sendable, Equatable {
    public let name: String
  }

  private let getSecretHandler: (@Sendable (String) async throws -> String)?
  private let closeHandler: (@Sendable () async -> Void)?

  public private(set) var getSecretCalls: [GetSecretCall] = []
  public private(set) var closeCallCount = 0

  public init(
    getSecretHandler: (@Sendable (String) async throws -> String)? = nil,
    closeHandler: (@Sendable () async -> Void)? = nil
  ) {
    self.getSecretHandler = getSecretHandler
    self.closeHandler = closeHandler
  }

  public func getSecret(name: String) async throws -> String {
    getSecretCalls.append(GetSecretCall(name: name))
    if let getSecretHandler {
      return try await getSecretHandler(name)
    }
    return ""
  }

  public func close() async {
    closeCallCount += 1
    await closeHandler?()
  }
}
