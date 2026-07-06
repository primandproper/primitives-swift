import CircuitBreaking
import DurationWire
import Foundation

/// Configuration for the OpenAI embeddings backend, ported from platform-go's `openai.Config`
/// (`embeddings/openai/config.go`):
/// ```go
/// type Config struct {
///     APIKey       string        `env:"API_KEY"       json:"apiKey,omitempty"`
///     BaseURL      string        `env:"BASE_URL"      json:"baseURL,omitempty"`
///     DefaultModel string        `env:"DEFAULT_MODEL" json:"defaultModel,omitempty"`
///     Timeout      time.Duration `env:"TIMEOUT"       json:"timeout"`
/// }
/// ```
/// Per the settled port architecture, Go's `env:` tags are dropped (iOS apps don't read the environment);
/// only the JSON contract survives, byte-compatible with a Go peer (`omitempty` strings, nanosecond
/// `timeout`) — the identical move `Sources/LLM`'s `LLMProviderConfig` makes for the same four fields.
///
/// **Deviation: an added ``circuitBreaker`` field.** Go's struct has no circuit-breaker field at all —
/// this is a deliberate port-side hardening, not a literal translation, applying the settled rule that a
/// remote-backed module embeds a `CircuitBreaking.CircuitBreakerConfig` in its wire config (the same move
/// `Analytics`'s `SourceConfig` and `FeatureFlags`'s `PostHogConfig` make). `{}` still decodes
/// successfully — a missing `circuitBreaker` key defaults to `CircuitBreakerConfig()`.
public struct OpenAIEmbedderConfig: Codable, Sendable, Equatable {
  /// The provider API key. Required (see ``validate()``).
  public var apiKey: String
  /// Optional override of the provider's base URL (self-hosted / proxy / compatible endpoint). Empty
  /// means OpenAI's default host.
  public var baseURL: String
  /// Optional default model, used when no per-instance model is otherwise resolved. Empty means
  /// ``OpenAIEmbedder``'s built-in fallback (`text-embedding-3-small`).
  public var defaultModel: String
  /// Request timeout. `.zero` means the provider default. Maps onto
  /// `URLSessionConfiguration.timeoutIntervalForRequest`.
  public var timeout: Duration
  /// The circuit breaker guarding every request through ``OpenAIEmbedder``. See the type doc for why this
  /// has no Go analogue.
  public var circuitBreaker: CircuitBreakerConfig

  public init(
    apiKey: String = "", baseURL: String = "", defaultModel: String = "", timeout: Duration = .zero,
    circuitBreaker: CircuitBreakerConfig = CircuitBreakerConfig()
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.defaultModel = defaultModel
    self.timeout = timeout
    self.circuitBreaker = circuitBreaker
  }

  /// Validates the config, mirroring Go's ozzo-validation `APIKey` required-rule. Throws a single
  /// ``EmbeddingsError/missingAPIKey`` rather than Go's field-error map.
  public func validate() throws {
    if apiKey.isEmpty {
      throw EmbeddingsError.missingAPIKey
    }
  }

  // MARK: - Codable (omitempty strings + nanosecond duration + embedded circuit breaker)

  private enum CodingKeys: String, CodingKey {
    case apiKey
    case baseURL
    case defaultModel
    case timeout
    case circuitBreaker
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? ""
    timeout = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .timeout) ?? 0)
    circuitBreaker =
      try c.decodeIfPresent(CircuitBreakerConfig.self, forKey: .circuitBreaker)
      ?? CircuitBreakerConfig()
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    // Go's `omitempty` drops empty strings from the object; reproduce that so a re-encoded config matches
    // a Go peer byte-for-byte.
    if !apiKey.isEmpty { try c.encode(apiKey, forKey: .apiKey) }
    if !baseURL.isEmpty { try c.encode(baseURL, forKey: .baseURL) }
    if !defaultModel.isEmpty { try c.encode(defaultModel, forKey: .defaultModel) }
    try c.encode(timeout.wholeNanoseconds, forKey: .timeout)
    try c.encode(circuitBreaker, forKey: .circuitBreaker)
  }
}
