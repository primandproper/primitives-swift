/// The provider seam, ported from platform-go's `llm.Provider` interface (`llm.go`).
///
/// Go's whole public surface is one method:
/// ```go
/// type Provider interface {
///     Completion(ctx context.Context, params CompletionParams) (*CompletionResult, error)
/// }
/// ```
/// Single-shot, text-only, chat-shaped. This is the faithful Swift analogue: `context.Context` becomes
/// structured-concurrency cancellation (a cancelled `Task` unwinds the underlying `URLSession` call), and
/// Go's `(*CompletionResult, error)` becomes a non-optional return that `throws` — a completion either
/// yields content or throws an ``LLMError``.
///
/// Kept intentionally minimal (one `async` method) so a Foundation Models `LanguageModelExecutor` adapter
/// could wrap a conforming provider on iOS 26+ without reshaping the protocol. See ``LLM``.
public protocol LLMProvider: Sendable {
  /// Runs a single chat completion for `params`, returning the assistant's text.
  func completion(_ params: CompletionParams) async throws -> CompletionResult
}

/// A chat message, ported from platform-go's `llm.Message`.
///
/// Go models `Role` as a bare `string` documented to take `"user"`, `"assistant"`, `"system"`, or
/// `"tool"`; Swift promotes that documented set to ``MessageRole``. `Content` is plain text — the
/// platform layer carries no multimodal parts or tool-call payloads (those exist only in the any-llm layer
/// Go never exposes).
public struct Message: Sendable, Equatable {
  public var role: MessageRole
  public var content: String

  public init(role: MessageRole, content: String) {
    self.role = role
    self.content = content
  }
}

/// The chat roles platform-go's `llm.Message.Role` documents. A closed enum in Swift where Go used a
/// bare string; the raw values are the exact wire tokens each provider expects.
public enum MessageRole: String, Sendable, Codable, Equatable, CaseIterable {
  case user
  case assistant
  case system
  case tool
}

/// Parameters for a completion, ported from platform-go's `llm.CompletionParams`.
///
/// Just the model id and the message list — none of any-llm's `Temperature`/`MaxTokens`/`Tools`/… are
/// present, because the platform interface never surfaced them. An empty ``model`` falls back to the
/// provider's configured default, then to the provider's built-in default (mirroring Go's two-step
/// fallback in each provider's `Completion`).
public struct CompletionParams: Sendable, Equatable {
  public var model: String
  public var messages: [Message]

  public init(model: String = "", messages: [Message]) {
    self.model = model
    self.messages = messages
  }
}

/// The result of a completion, ported from platform-go's `llm.CompletionResult`.
///
/// Just the assistant's text. Go records usage/finish-reason onto telemetry inside the provider but drops
/// them from the returned struct; this port does the same (they land on the span, not here).
public struct CompletionResult: Sendable, Equatable {
  public var content: String

  public init(content: String) {
    self.content = content
  }
}
