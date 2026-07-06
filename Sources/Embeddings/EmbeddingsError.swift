import Foundation

/// Errors surfaced by the ``Embedder`` conformers.
///
/// Go's `embeddings` package leans on plain `fmt`-wrapped errors per backend (no shared sentinel family
/// the way `llm` leans on any-llm's typed errors). This port instead reuses the *classification* approach
/// `Sources/LLM`'s `LLMError` settled on: because ``OpenAIEmbedder`` makes the HTTP call itself, it maps
/// HTTP status (and, for 429, the `Retry-After` header) onto the equivalent case here, giving Search a
/// typed, switchable failure rather than an opaque wrapped string. As with `LLMError`, **a 429 comes back
/// as ``rateLimit(retryAfter:)`` and is never retried internally** — compose `Retry` around
/// ``Embedder/embed(_:)`` for backoff, matching Go's embeddings backends, none of which retry either.
public enum EmbeddingsError: Error, Equatable, Sendable {
  /// The provider config is missing its API key.
  case missingAPIKey
  /// The config failed validation. Carries the human-readable reason.
  case invalidConfig(String)
  /// Authentication failed (HTTP 401/403).
  case authentication
  /// The provider rate-limited the request (HTTP 429). Carries the `Retry-After` delay in seconds when
  /// the provider supplied one. Not retried here by design.
  case rateLimit(retryAfter: TimeInterval?)
  /// The requested model does not exist (HTTP 404, or a 400 the provider attributes to the model).
  /// Carries the model id.
  case modelNotFound(String)
  /// The request was rejected as invalid (HTTP 400). Carries the provider's message.
  case invalidRequest(String)
  /// A non-2xx status not covered by a more specific case. Carries status + body message.
  case provider(status: Int, message: String)
  /// A 2xx response whose body couldn't be decoded into the expected shape. Carries a short reason.
  case malformedResponse(String)
  /// The remote request was refused by an open circuit breaker before it reached the network. The
  /// ``Embedder``-level analogue of `HTTPClient`'s `HTTPClientError.circuitBroken`.
  case circuitBroken
  /// No on-device embedding model is available for the requested language (``OnDeviceEmbedder``). Carries
  /// the BCP-47 language code that was requested.
  case embeddingUnavailable(String)
  /// The on-device model produced no vector for the given text (``OnDeviceEmbedder``) — e.g. empty input
  /// the tokenizer reduces to nothing. Carries the input that failed.
  case embeddingFailed(String)

  public var description: String {
    switch self {
    case .missingAPIKey: return "missing API key"
    case .invalidConfig(let reason): return "invalid embeddings config: \(reason)"
    case .authentication: return "embeddings authentication failed"
    case .rateLimit(let retryAfter):
      if let retryAfter { return "embeddings rate limited; retry after \(retryAfter)s" }
      return "embeddings rate limited"
    case .modelNotFound(let model): return "embeddings model not found: \(model)"
    case .invalidRequest(let message): return "invalid embeddings request: \(message)"
    case .provider(let status, let message):
      return "embeddings provider error (\(status)): \(message)"
    case .malformedResponse(let reason): return "malformed embeddings response: \(reason)"
    case .circuitBroken: return "embeddings circuit breaker open; refusing request"
    case .embeddingUnavailable(let language):
      return "no on-device embedding model available for language: \(language)"
    case .embeddingFailed(let text): return "on-device embedding failed for input: \(text)"
    }
  }
}

extension EmbeddingsError: LocalizedError {
  public var errorDescription: String? { description }
}

extension EmbeddingsError {
  /// Classifies a non-2xx HTTP response into the matching case, mirroring `LLMError.classify`'s
  /// status→case mapping exactly (see that type for the rationale). `message` is the best
  /// human-readable string the caller could pull from the error body; `model` is the request's resolved
  /// model id (used to name a `.modelNotFound`).
  static func classify(
    status: Int, message: String, model: String, retryAfterHeader: String?
  ) -> EmbeddingsError {
    switch status {
    case 401, 403:
      return .authentication
    case 404:
      return .modelNotFound(model)
    case 429:
      return .rateLimit(retryAfter: parseRetryAfter(retryAfterHeader))
    case 400:
      let lowered = message.lowercased()
      if lowered.contains("model")
        && (lowered.contains("not found") || lowered.contains("does not exist"))
      {
        return .modelNotFound(model)
      }
      return .invalidRequest(message)
    default:
      return .provider(status: status, message: message)
    }
  }

  /// Parses a `Retry-After` header into a delay in seconds, honoring both RFC 7231 forms — a
  /// *delta-seconds* integer and an *HTTP-date* (measured from `now`) — the same parser `LLMError` and
  /// `HTTPClient` share. Returns `nil` when the header is absent or unparseable; a past date or
  /// non-positive count yields `0`.
  static func parseRetryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
    guard let raw = header?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

    if let seconds = TimeInterval(raw) {
      return max(0, seconds)
    }
    if let date = httpDateFormatter.date(from: raw) {
      return max(0, date.timeIntervalSince(now))
    }
    return nil
  }

  /// RFC 7231 IMF-fixdate formatter (`en_US_POSIX`, GMT), mirroring `LLMError`'s. Held as a shared
  /// `static let` rather than rebuilt on every rate-limited response.
  private static let httpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter
  }()
}
