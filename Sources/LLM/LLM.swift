/// # LLM
///
/// Ported from platform-go's `llm` package (`llm.go` + `openai/`, `anthropic/`, `noop/`, `mock/`,
/// `config/`) — the client-relevant slice, per the iOS-only scope of this port (see `PORTING.md`).
///
/// ## What the Go package does, and how this differs
///
/// Go's `llm` exposes a deliberately tiny seam — a single-method ``LLMProvider`` (`Completion`) over a
/// chat-shaped request (`{Model, [Message{Role, Content}]}`) returning `{Content}` — and delegates the
/// actual provider calls to `mozilla-ai/any-llm-go`, an LLM router that normalizes OpenAI/Anthropic (and
/// more) behind one interface. **None of any-llm's breadth is surfaced through the platform API**:
/// streaming, tools, embeddings, structured output, multimodal, and reasoning all live one layer down and
/// are never exposed. So the thing worth porting is not the router — it's the two thin provider adapters
/// and the single completion call.
///
/// This port replaces any-llm's HTTP layer with **direct `URLSession` + `Codable`** calls to each
/// provider's REST API (OpenAI chat-completions, Anthropic messages), the same no-dependency, wire-native
/// approach the rest of the port takes (`HTTPClient`, `EventStream`, `Capitalism`). There is no SPM
/// dependency: the two vendor REST surfaces are simple enough that a router library buys nothing a client
/// needs.
///
/// What travels over intact:
///   * ``LLMProvider`` — the provider-seam protocol (``LLMProvider/completion(_:)``), over ``Message`` /
///     ``CompletionParams`` / ``CompletionResult``.
///   * ``OpenAIProvider`` and ``AnthropicProvider`` — **live** adapters (`URLSession`), each wiring the
///     three-pillar telemetry Go's providers wire (an ``Observability/Observer`` operation plus
///     request/error counters and a `*_latency_ms` histogram) and, like Go, **not** retrying — a 429 is
///     surfaced as ``LLMError/rateLimit(retryAfter:)`` for the caller to back off on (wrap with `Retry`).
///   * ``NoopLLMProvider`` and actor ``LLMProviderMock`` — the no-op default and test double.
///   * ``OpenAIConfig`` / ``AnthropicConfig`` / ``LLMConfig`` — the wire-compatible `Codable` config tree
///     (Go's `env:` tags dropped per the settled architecture; JSON keys and nanosecond `Duration`
///     encoding preserved) plus ``provideLLMProvider(config:pillars:)``, the provider selector.
///
/// ## Foundation Models seam (deliberately not adopted here)
///
/// iOS 26's Foundation Models framework shipped a public `LanguageModel` / `LanguageModelExecutor`
/// provider protocol — the native analogue of any-llm's router — which would grant guided generation,
/// tool calling, and streaming for free. It is **not** adopted as this module's core because it pins the
/// deployment target to iOS 26, whereas this package targets iOS 16. ``LLMProvider`` is intentionally
/// shaped as a plain async single-method seam so a `LanguageModelExecutor` adapter can wrap it later,
/// without rework, if the floor is ever raised.
///
/// Dropped (server-side / no iOS analogue): the `samber/do` DI registration (`config/do.go`) — replaced
/// everywhere in this port by plain constructor injection.
public enum LLM {}
