/// A test double for ``LLMProvider``, ported from platform-go's moq-generated `llmmock.ProviderMock`
/// (`mock/provider_mock.go`).
///
/// Go's moq output is a struct with a `CompletionFunc` field plus mutex-guarded call recording; calling a
/// method whose `*Func` is unset panics. The Swift port keeps the shape — an optional handler closure plus
/// a recorded-calls list — but trades panic-on-unset for a quieter default: an unset handler returns empty
/// content. Thread safety comes from this being an `actor` rather than hand-rolled locks, matching
/// ``Analytics/EventReporterMock``.
public actor LLMProviderMock: LLMProvider {
  public var completionHandler: (@Sendable (CompletionParams) async throws -> CompletionResult)?

  public private(set) var completionCalls: [CompletionParams] = []

  public init(
    completionHandler: (@Sendable (CompletionParams) async throws -> CompletionResult)? = nil
  ) {
    self.completionHandler = completionHandler
  }

  /// (Re)configures the handler after construction. `completionHandler` is a `public var` on an actor,
  /// so it can't be assigned from outside (`mock.completionHandler = …` is rejected under Swift 6
  /// actor isolation); this async mutator is the supported way to script the double post-init (REPO-05).
  public func setCompletionHandler(
    _ handler: (@Sendable (CompletionParams) async throws -> CompletionResult)?
  ) {
    completionHandler = handler
  }

  public func completion(_ params: CompletionParams) async throws -> CompletionResult {
    completionCalls.append(params)
    if let completionHandler {
      return try await completionHandler(params)
    }
    return CompletionResult(content: "")
  }
}
