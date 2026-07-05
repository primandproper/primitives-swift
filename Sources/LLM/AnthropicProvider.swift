import Foundation
import Observability

/// A **live** Anthropic-backed ``LLMProvider``, ported from platform-go's `llm/anthropic`.
///
/// Go wraps any-llm's Anthropic provider; this calls Anthropic's `POST /v1/messages` directly. The Messages
/// API is shaped differently from OpenAI's chat-completions — differences any-llm hid and this adapter must
/// handle explicitly:
///   * **`system` is a top-level field**, not a message role. Any ``MessageRole/system`` messages are
///     hoisted out and joined (`\n\n`) into the request's `system` string.
///   * **`max_tokens` is required.** The platform ``CompletionParams`` carries none (it never exposed
///     any-llm's `MaxTokens`), so this sends ``defaultMaxTokens`` — any-llm supplies a default here too.
///   * **`tool` role** isn't a plain text turn in the Messages API (it's a `tool_result` content block);
///     for this text-only port a ``MessageRole/tool`` message is folded into a `user` turn. Wire up proper
///     tool-result blocks only if a flow needs them.
///
/// Telemetry, model fallback, and the no-retry contract are identical to ``OpenAIProvider`` (shared via
/// ``LLMHTTP``); metrics emit as `anthropic_llm_*`.
public struct AnthropicProvider: LLMProvider {
  /// Observability/metric name, matching Go's `const name = "anthropic_llm"`.
  public static let o11yName = "anthropic_llm"
  /// Built-in fallback model, matching Go's final `model = "claude-sonnet-4-20250514"`.
  public static let defaultModel = "claude-sonnet-4-20250514"
  /// Anthropic's default host, used when the config leaves ``LLMProviderConfig/baseURL`` empty.
  public static let defaultBaseURL = "https://api.anthropic.com"
  /// The `anthropic-version` header value the Messages API requires.
  public static let apiVersion = "2023-06-01"
  /// `max_tokens` sent on every request, since the platform request model carries none and the Messages
  /// API requires it. A generous default suited to the Sonnet-class default model.
  public static let defaultMaxTokens = 4096

  private let session: URLSession
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let apiKey: String
  private let baseURL: String
  private let configuredDefaultModel: String

  /// Primary initializer — inject an already-built session, observer, and metrics provider (the test seam).
  public init(
    session: URLSession,
    observer: any Observer,
    metrics: any MetricsProvider,
    apiKey: String,
    baseURL: String = AnthropicProvider.defaultBaseURL,
    defaultModel: String = ""
  ) {
    self.session = session
    self.observer = observer
    self.metrics = metrics
    self.apiKey = apiKey
    self.baseURL = baseURL.isEmpty ? AnthropicProvider.defaultBaseURL : baseURL
    self.configuredDefaultModel = defaultModel
  }

  /// Convenience initializer — the analogue of Go's `anthropic.NewProvider(...)`.
  public init(config: LLMProviderConfig, pillars: Pillars) {
    self.init(
      session: makeLLMSession(timeout: config.timeout),
      observer: LiveObserver(
        name: AnthropicProvider.o11yName, logger: pillars.logger, tracer: pillars.tracer),
      metrics: pillars.metrics,
      apiKey: config.apiKey,
      baseURL: config.baseURL,
      defaultModel: config.defaultModel
    )
  }

  public func completion(_ params: CompletionParams) async throws -> CompletionResult {
    try await runInstrumentedCompletion(
      params: params,
      observer: observer,
      metrics: metrics,
      metricName: Self.o11yName,
      builtinDefaultModel: Self.defaultModel,
      configuredDefaultModel: configuredDefaultModel
    ) { model in
      try await perform(model: model, messages: params.messages)
    }
  }

  // MARK: - Transport

  private struct RequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [WireMessage]
    enum CodingKeys: String, CodingKey {
      case model
      case maxTokens = "max_tokens"
      case system
      case messages
    }
  }

  private struct ResponseBody: Decodable {
    struct ContentBlock: Decodable {
      let type: String
      let text: String?
    }
    struct Usage: Decodable {
      let inputTokens: Int?
      let outputTokens: Int?
      enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
      }
    }
    let content: [ContentBlock]
    let stopReason: String?
    let usage: Usage?
    enum CodingKeys: String, CodingKey {
      case content
      case stopReason = "stop_reason"
      case usage
    }
  }

  private func perform(model: String, messages: [Message]) async throws -> RawCompletion {
    // Hoist system turns to the top-level `system`; map the rest to user/assistant turns (tool → user).
    var systemParts: [String] = []
    var wireMessages: [WireMessage] = []
    for message in messages {
      switch message.role {
      case .system:
        systemParts.append(message.content)
      case .user, .tool:
        wireMessages.append(WireMessage(role: "user", content: message.content))
      case .assistant:
        wireMessages.append(WireMessage(role: "assistant", content: message.content))
      }
    }

    let body = RequestBody(
      model: model,
      maxTokens: Self.defaultMaxTokens,
      system: systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n"),
      messages: wireMessages)

    guard let url = URL(string: "\(baseURL)/v1/messages") else {
      throw LLMError.invalidConfig("invalid base URL: \(baseURL)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)

    let data = try await sendLLMRequest(request, session: session, model: model)

    let decoded: ResponseBody
    do {
      decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
    } catch {
      throw LLMError.malformedResponse("\(error)")
    }
    // any-llm's `ContentString()` concatenates the text blocks; do the same, skipping non-text blocks.
    let text = decoded.content.filter { $0.type == "text" }.compactMap { $0.text }.joined()
    let totalTokens: Int?
    if let usage = decoded.usage, usage.inputTokens != nil || usage.outputTokens != nil {
      totalTokens = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
    } else {
      totalTokens = nil
    }
    return RawCompletion(content: text, totalTokens: totalTokens, finishReason: decoded.stopReason)
  }
}
