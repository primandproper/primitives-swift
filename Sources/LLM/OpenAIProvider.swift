import Foundation
import Observability

/// A **live** OpenAI-backed ``LLMProvider``, ported from platform-go's `llm/openai`.
///
/// Go wraps any-llm's OpenAI provider; this calls OpenAI's `POST /chat/completions` directly with
/// `URLSession` + `Codable`. The three-pillar telemetry Go wires (observer operation + request/error
/// counters + `openai_llm_latency_ms` histogram) is reproduced in ``LLMHTTP`` and shared with
/// ``AnthropicProvider``, so this type is just request-building, response-parsing, and the injected
/// dependencies. Like Go, it **does not retry** — a 429 surfaces as ``LLMError/rateLimit(retryAfter:)``.
public struct OpenAIProvider: LLMProvider {
  /// Observability/metric name, matching Go's `const name = "openai_llm"`. Metrics emit as
  /// `openai_llm_requests` / `openai_llm_errors` / `openai_llm_latency_ms`.
  public static let o11yName = "openai_llm"
  /// Built-in fallback model, matching Go's final `model = "gpt-4o-mini"`.
  public static let defaultModel = "gpt-4o-mini"
  /// OpenAI's default host + version prefix, used when the config leaves ``LLMProviderConfig/baseURL``
  /// empty (the analogue of any-llm's default base URL).
  public static let defaultBaseURL = "https://api.openai.com/v1"

  private let session: URLSession
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let apiKey: String
  private let baseURL: String
  private let configuredDefaultModel: String

  /// Primary initializer — inject an already-built session, observer, and metrics provider. The seam tests
  /// use: pass a `URLSession` backed by a `URLProtocol` stub and a ``Observability/RecordingObserver`` to
  /// exercise the provider hermetically, with no network.
  public init(
    session: URLSession,
    observer: any Observer,
    metrics: any MetricsProvider,
    apiKey: String,
    baseURL: String = OpenAIProvider.defaultBaseURL,
    defaultModel: String = ""
  ) {
    self.session = session
    self.observer = observer
    self.metrics = metrics
    self.apiKey = apiKey
    self.baseURL = baseURL.isEmpty ? OpenAIProvider.defaultBaseURL : baseURL
    self.configuredDefaultModel = defaultModel
  }

  /// Convenience initializer building the session and observer from config + pillars — the analogue of
  /// Go's `openai.NewProvider(cfg, logger, tracerProvider, metricsProvider)`.
  public init(config: LLMProviderConfig, pillars: Pillars) {
    self.init(
      session: makeLLMSession(timeout: config.timeout),
      observer: LiveObserver(
        name: OpenAIProvider.o11yName, logger: pillars.logger, tracer: pillars.tracer),
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
    let messages: [WireMessage]
  }

  private struct ResponseBody: Decodable {
    struct Choice: Decodable {
      let message: Message
      let finishReason: String?
      struct Message: Decodable { let content: String? }
      enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
      }
    }
    struct Usage: Decodable {
      let totalTokens: Int?
      enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
    }
    let choices: [Choice]
    let usage: Usage?
  }

  private func perform(model: String, messages: [Message]) async throws -> RawCompletion {
    // OpenAI accepts every documented role (system/user/assistant/tool) straight in the messages array, so
    // no reshaping is needed — unlike Anthropic. See ``AnthropicProvider``.
    let body = RequestBody(
      model: model,
      messages: messages.map { WireMessage(role: $0.role.rawValue, content: $0.content) })

    guard let url = URL(string: "\(baseURL)/chat/completions") else {
      throw LLMError.invalidConfig("invalid base URL: \(baseURL)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)

    let data = try await sendLLMRequest(request, session: session, model: model)

    let decoded: ResponseBody
    do {
      decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
    } catch {
      throw LLMError.malformedResponse("\(error)")
    }
    // Go extracts `Choices[0].Message.ContentString()` and returns "" when there are no choices.
    return RawCompletion(
      content: decoded.choices.first?.message.content ?? "",
      totalTokens: decoded.usage?.totalTokens,
      finishReason: decoded.choices.first?.finishReason)
  }
}
