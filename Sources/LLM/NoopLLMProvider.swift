/// A no-op ``LLMProvider``, ported from platform-go's `llm/noop`. The safe default when no provider is
/// configured (or an unrecognized one is): every completion returns empty content rather than leaving
/// callers nil-checking a provider that may not exist. Mirrors Go's `noopProvider` returning
/// `&CompletionResult{}`.
public struct NoopLLMProvider: LLMProvider {
  public init() {}

  public func completion(_ params: CompletionParams) async throws -> CompletionResult {
    CompletionResult(content: "")
  }
}
