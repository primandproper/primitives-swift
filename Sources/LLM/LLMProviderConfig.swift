import DurationWire
import Foundation

/// Per-provider client config, ported from platform-go's `openai.Config` **and** `anthropic.Config`.
///
/// Those two Go structs are byte-identical — same four fields, same `env:`/`json:` tags, same
/// `APIKey`-required validation — so this port carries a single shared type used for both the `openai` and
/// `anthropic` slots of ``LLMConfig`` rather than duplicating it. (What genuinely differs between the two
/// providers — the built-in default model, the wire shape — lives in ``OpenAIProvider`` /
/// ``AnthropicProvider``, not here.)
///
/// Per the settled port architecture, Go's `env:` tags are dropped (iOS apps don't read the environment);
/// only the JSON contract survives. Go marks `apiKey`/`baseURL`/`defaultModel` `omitempty` and `timeout`
/// not — so ``encode(to:)`` omits empty strings and always emits ``timeout`` as **integer nanoseconds**
/// (Go's `time.Duration` wire form), and ``init(from:)`` tolerates any of them being absent, exactly as a
/// partial JSON object unmarshals into the Go struct.
public struct LLMProviderConfig: Codable, Sendable, Equatable {
  /// The provider API key. Required (see ``validate()``); the analogue of any-llm's `WithAPIKey`.
  public var apiKey: String
  /// Optional override of the provider's base URL (self-hosted / proxy / compatible endpoint). Empty means
  /// the provider's default host. any-llm's `WithBaseURL`.
  public var baseURL: String
  /// Optional default model, used when a ``CompletionParams/model`` is empty. Empty means the provider's
  /// built-in fallback (`gpt-4o-mini` / `claude-sonnet-4-20250514`).
  public var defaultModel: String
  /// Request timeout. `.zero` means the provider default (120s, matching any-llm's default). Maps onto
  /// `URLSessionConfiguration.timeoutIntervalForRequest`. any-llm's `WithTimeout`.
  public var timeout: Duration

  public init(
    apiKey: String = "", baseURL: String = "", defaultModel: String = "", timeout: Duration = .zero
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.defaultModel = defaultModel
    self.timeout = timeout
  }

  /// Validates the config, mirroring Go's ozzo-validation `APIKey` required-rule. Throws a single
  /// ``LLMError/missingAPIKey`` rather than Go's field-error map.
  public func validate() throws {
    if apiKey.isEmpty {
      throw LLMError.missingAPIKey
    }
  }

  // MARK: - Codable (omitempty strings + nanosecond duration contract)

  private enum CodingKeys: String, CodingKey {
    case apiKey
    case baseURL
    case defaultModel
    case timeout
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? ""
    timeout = .nanoseconds(try c.decodeIfPresent(Int64.self, forKey: .timeout) ?? 0)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    // Go's `omitempty` drops empty strings from the object; reproduce that so a re-encoded config matches
    // a Go peer byte-for-byte.
    if !apiKey.isEmpty { try c.encode(apiKey, forKey: .apiKey) }
    if !baseURL.isEmpty { try c.encode(baseURL, forKey: .baseURL) }
    if !defaultModel.isEmpty { try c.encode(defaultModel, forKey: .defaultModel) }
    try c.encode(timeout.wholeNanoseconds, forKey: .timeout)
  }
}
