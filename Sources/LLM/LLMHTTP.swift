import Foundation
import Observability

/// A provider's transport result before it's narrowed to the public ``CompletionResult`` — carries the
/// extras Go records onto the span (`llm.tokens.total`, `llm.finish_reason`) but drops from the return.
struct RawCompletion {
  var content: String
  var totalTokens: Int?
  var finishReason: String?
}

/// The error-body shape both providers share on a non-2xx: OpenAI returns `{"error":{"message":…}}` and
/// Anthropic `{"type":"error","error":{"message":…}}`, so decoding `error.message` covers both.
struct WireErrorBody: Decodable {
  struct Inner: Decodable { let message: String? }
  let error: Inner?
}

/// A chat message on the wire — OpenAI's `messages[]` element shape, reused for Anthropic's (whose
/// user/assistant turns are identically `{role, content}`).
struct WireMessage: Encodable {
  let role: String
  let content: String
}

/// Builds the `URLSession` a provider makes its calls through, the analogue of any-llm's HTTP client
/// construction. A `.zero` timeout means any-llm's 120s default; the resource timeout is scaled 3× like
/// `HTTPClientConfig` does.
func makeLLMSession(timeout: Duration) -> URLSession {
  let effective = timeout > .zero ? timeout : .seconds(120)
  let config = URLSessionConfiguration.default
  config.timeoutIntervalForRequest = effective.timeInterval
  config.timeoutIntervalForResource = (effective * 3).timeInterval
  return URLSession(configuration: config)
}

/// The shared instrumented completion wrapper both providers run their transport through — the faithful
/// analogue of the identical body Go's `openaiProvider.Completion` and `anthropicProvider.Completion`
/// share. It resolves the model (params → configured default → built-in default), opens an
/// ``Observability/Observer`` operation, records `llm.model`/`llm.message_count` on the way in and
/// tokens/finish-reason on the way out, always emits the `_latency_ms` histogram, and increments the
/// `_requests`/`_errors` counters — matching Go's metric names exactly.
///
/// Error handling mirrors `HTTPClient`: a typed ``LLMError`` (the classified provider failure) is recorded
/// and rethrown **raw** so callers can `catch LLMError.rateLimit(let retryAfter)`; cancellation propagates
/// raw so a retry wrapper sees it as terminal; any other unexpected error is wrapped with `op.error` for
/// context, as Go's `op.Error` wraps.
func runInstrumentedCompletion(
  params: CompletionParams,
  observer: any Observer,
  metrics: any MetricsProvider,
  metricName: String,
  builtinDefaultModel: String,
  configuredDefaultModel: String,
  transport: (_ model: String) async throws -> RawCompletion
) async throws -> CompletionResult {
  try await observer.operation(name: "Completion") { op in
    var model = params.model
    if model.isEmpty { model = configuredDefaultModel }
    if model.isEmpty { model = builtinDefaultModel }

    op.set("llm.model", model).set("llm.message_count", params.messages.count)

    let start = DispatchTime.now()
    defer {
      let elapsedNanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
      metrics.histogram("\(metricName)_latency_ms").record(Double(elapsedNanos) / 1_000_000)
    }

    do {
      let raw = try await transport(model)
      metrics.counter("\(metricName)_requests").increment()
      if let totalTokens = raw.totalTokens { op.set("llm.tokens.total", totalTokens) }
      if let finishReason = raw.finishReason { op.set("llm.finish_reason", finishReason) }
      return CompletionResult(content: raw.content)
    } catch let error as LLMError {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "completing request")
      throw error
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        op.acknowledge(error, "completion cancelled")
        throw error
      }
      throw op.error(error, "completing request")
    }
  }
}

/// Runs `request` and returns its body, mapping a non-2xx status onto the classified ``LLMError`` (pulling
/// the human-readable `error.message` from the body and `Retry-After` from the headers) and a non-HTTP
/// response onto ``LLMError/provider(status:message:)``. Shared by both providers' transports.
func sendLLMRequest(
  _ request: URLRequest, session: URLSession, model: String
) async throws -> Data {
  let (data, response) = try await session.data(for: request)
  guard let http = response as? HTTPURLResponse else {
    throw LLMError.provider(status: 0, message: "response was not an HTTP response")
  }
  guard (200..<300).contains(http.statusCode) else {
    let message =
      (try? JSONDecoder().decode(WireErrorBody.self, from: data))?.error?.message
      ?? String(data: data, encoding: .utf8).map { $0.isEmpty ? "no response body" : $0 }
      ?? "no response body"
    let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
    throw LLMError.classify(
      status: http.statusCode, message: message, model: model, retryAfterHeader: retryAfter)
  }
  return data
}
