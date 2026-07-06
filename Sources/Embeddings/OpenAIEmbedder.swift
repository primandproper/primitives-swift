import CircuitBreaking
import Foundation
import HTTPClient
import Observability

/// A **live** OpenAI-backed ``Embedder``, ported from platform-go's `embeddings/openai`.
///
/// Go calls OpenAI's `POST /v1/embeddings` directly with `net/http` + `encoding/json`; this calls the
/// same endpoint through ``HTTPClient`` + `Codable`, mirroring `Sources/LLM`'s `OpenAIProvider` pattern
/// exactly for the request/response shape, metric naming, and error classification (see ``Embeddings``
/// and ``EmbeddingsError``). Unlike `OpenAIProvider`, the transport runs through ``HTTPClient`` rather
/// than a bare `URLSession`, so this backend composes with whatever breaker ``HTTPClient`` is given.
/// Like Go, and like `OpenAIProvider`, it **does not retry** — a 429 surfaces as
/// ``EmbeddingsError/rateLimit(retryAfter:)``.
///
/// **Circuit breaker note (base-inconsistency).** ``OpenAIEmbedderConfig`` carries a
/// `CircuitBreaking.CircuitBreakerConfig` per the settled rule that a remote-backed module embeds one
/// (see that type). This code's ``HTTPClient``, however, still models circuit breaking with its own
/// small *local* `CircuitBreaker` protocol (synchronous `failed()`/`succeeded()`) predating the shared,
/// actor-backed `CircuitBreaking` module — its own doc comment (`Sources/HTTPClient/CircuitBreaker.swift`)
/// notes the two are meant to be reconciled "at the wiring site" once adopted. The two protocols are not
/// bridgeable without either blocking on the actor or reimplementing its bookkeeping, so
/// ``init(config:pillars:)`` does **not** attempt it: it builds `HTTPClient` with its own
/// `NoopCircuitBreaker()`, and ``OpenAIEmbedderConfig/circuitBreaker`` stays a carried-but-inert wire
/// field for now (the identical situation `FeatureFlags`'s `LaunchDarklyConfig` documents for its own
/// unused `circuitBreakerConfig`). Once `HTTPClient` depends on `CircuitBreaking` — as it already does on
/// this port's `main` branch — this initializer can wire `circuitBreaker.provideCircuitBreaker(...)`
/// straight through with no change to ``OpenAIEmbedderConfig``.
public struct OpenAIEmbedder: Embedder {
  /// Observability/metric name. Metrics emit as `openai_embeddings_requests` / `openai_embeddings_errors`
  /// / `openai_embeddings_latency_ms`.
  public static let o11yName = "openai_embeddings"
  /// Built-in fallback model, matching Go's `openai.defaultModel`.
  public static let defaultModel = "text-embedding-3-small"
  /// OpenAI's default host + version prefix, used when the config leaves
  /// ``OpenAIEmbedderConfig/baseURL`` empty.
  public static let defaultBaseURL = "https://api.openai.com/v1"

  /// Known output widths for OpenAI's published embedding models, used to resolve ``dimensions``
  /// synchronously at construction (Go only learns this from `len(response.Data[0].Embedding)` on each
  /// call — this port promotes it to a fixed, up-front property; see ``Embedder/dimensions``). A model
  /// not in this table falls back to ``defaultModel``'s width, the same width ``defaultModel`` itself
  /// resolves to.
  public static let knownModelDimensions: [String: Int] = [
    "text-embedding-3-small": 1536,
    "text-embedding-3-large": 3072,
    "text-embedding-ada-002": 1536,
  ]

  public let dimensions: Int

  private let httpClient: HTTPClient
  private let observer: any Observer
  private let apiKey: String
  private let baseURL: String
  private let model: String
  private let metrics: any MetricsProvider

  /// Primary initializer — inject an already-built session, observer, metrics provider, and circuit
  /// breaker. The seam tests use: pass a `URLSession` backed by a `URLProtocol` stub and a
  /// ``Observability/RecordingObserver`` to exercise the embedder hermetically, with no network.
  public init(
    session: URLSession,
    observer: any Observer,
    metrics: any MetricsProvider,
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker(),
    apiKey: String,
    baseURL: String = OpenAIEmbedder.defaultBaseURL,
    defaultModel: String = ""
  ) {
    self.httpClient = HTTPClient(
      session: session, observer: observer, metrics: metrics, circuitBreaker: circuitBreaker)
    self.observer = observer
    self.metrics = metrics
    self.apiKey = apiKey
    self.baseURL = baseURL.isEmpty ? OpenAIEmbedder.defaultBaseURL : baseURL
    self.model = defaultModel.isEmpty ? OpenAIEmbedder.defaultModel : defaultModel
    self.dimensions =
      OpenAIEmbedder.knownModelDimensions[self.model]
      ?? OpenAIEmbedder
      .knownModelDimensions[OpenAIEmbedder.defaultModel]!
  }

  /// Convenience initializer building the session and observer from config + pillars — the analogue of
  /// Go's `openai.NewEmbedder(ctx, cfg, logger, tracer)`. See the type doc for why this does not (yet)
  /// build a live breaker from ``OpenAIEmbedderConfig/circuitBreaker``.
  public init(config: OpenAIEmbedderConfig, pillars: Pillars) {
    self.init(
      session: makeEmbeddingsSession(timeout: config.timeout),
      observer: LiveObserver(
        name: OpenAIEmbedder.o11yName, logger: pillars.logger, tracer: pillars.tracer),
      metrics: pillars.metrics,
      apiKey: config.apiKey,
      baseURL: config.baseURL,
      defaultModel: config.defaultModel
    )
  }

  public func embed(_ text: String) async throws -> [Float] {
    try await runInstrumentedEmbed(
      text: text,
      model: model,
      observer: observer,
      metrics: metrics,
      metricName: Self.o11yName
    ) { model in
      try await perform(model: model, text: text)
    }
  }

  // MARK: - Transport

  private struct RequestBody: Encodable {
    let input: String
    let model: String
    let encodingFormat: String

    enum CodingKeys: String, CodingKey {
      case input
      case model
      case encodingFormat = "encoding_format"
    }
  }

  private struct ResponseBody: Decodable {
    struct DataItem: Decodable { let embedding: [Double] }
    let data: [DataItem]
  }

  private func perform(model: String, text: String) async throws -> [Float] {
    let body = RequestBody(input: text, model: model, encodingFormat: "float")

    guard let url = URL(string: "\(baseURL)/embeddings") else {
      throw EmbeddingsError.invalidConfig("invalid base URL: \(baseURL)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)

    let response = try await httpClient.perform(request)

    guard response.isSuccess else {
      let message =
        (try? JSONDecoder().decode(EmbeddingsWireErrorBody.self, from: response.body))?.error?
        .message
        ?? String(data: response.body, encoding: .utf8).map {
          $0.isEmpty ? "no response body" : $0
        }
        ?? "no response body"
      throw EmbeddingsError.classify(
        status: response.statusCode, message: message, model: model,
        retryAfterHeader: response.headers["Retry-After"])
    }

    let decoded: ResponseBody
    do {
      decoded = try JSONDecoder().decode(ResponseBody.self, from: response.body)
    } catch {
      throw EmbeddingsError.malformedResponse("\(error)")
    }

    guard let first = decoded.data.first else {
      throw EmbeddingsError.malformedResponse("openai embedding response contained no data")
    }

    return first.embedding.map(Float.init)
  }
}
