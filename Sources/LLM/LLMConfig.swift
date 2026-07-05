import Foundation
import Observability

/// The recognized LLM backends, ported from the `ProviderOpenAI`/`ProviderAnthropic` string constants in
/// platform-go's `llm/config/config.go` (package `llmcfg`).
///
/// Go validates ``LLMConfig/provider`` as a bare string with `validation.In(ProviderOpenAI,
/// ProviderAnthropic, "")`, resolving an empty/unknown value to the noop provider. ``LLMConfig/provider``
/// keeps that raw-string shape for that lenient fallback; this closed enum is what a recognized string
/// resolves into.
public enum LLMProviderKind: String, Codable, Sendable, CaseIterable {
  case openai
  case anthropic
}

/// The top-level LLM configuration, ported from platform-go's `llmcfg.Config`:
/// ```go
/// type Config struct {
///   OpenAI    *openai.Config    `json:"openai"`
///   Anthropic *anthropic.Config `json:"anthropic"`
///   Provider  string            `json:"provider"`
/// }
/// ```
/// The two provider configs are optional (a deployment configures only the one it uses), and ``provider``
/// selects between them — empty or unrecognized resolving to a noop, exactly like Go's
/// `ProvideLLMProvider` `default` case. Wire keys: `openai`, `anthropic`, `provider`.
public struct LLMConfig: Codable, Sendable, Equatable {
  public var openai: LLMProviderConfig?
  public var anthropic: LLMProviderConfig?
  public var provider: String

  public init(
    openai: LLMProviderConfig? = nil,
    anthropic: LLMProviderConfig? = nil,
    provider: String = ""
  ) {
    self.openai = openai
    self.anthropic = anthropic
    self.provider = provider
  }

  private enum CodingKeys: String, CodingKey {
    case openai
    case anthropic
    case provider
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    openai = try c.decodeIfPresent(LLMProviderConfig.self, forKey: .openai)
    anthropic = try c.decodeIfPresent(LLMProviderConfig.self, forKey: .anthropic)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
  }

  /// The recognized provider ``provider`` resolves to, or `nil` for an empty/unknown value (→ noop). The
  /// analogue of Go's lowercase/trim before the switch in `ProvideLLMProvider`.
  public var resolvedProvider: LLMProviderKind? {
    LLMProviderKind(rawValue: provider.trimmingCharacters(in: .whitespaces).lowercased())
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`. When ``provider`` is set to a
  /// recognized backend, that backend's config must be present and valid; an empty ``provider`` (noop) is
  /// allowed with no provider config.
  public func validate() throws {
    let trimmed = provider.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return }
    guard let resolved = resolvedProvider else {
      throw LLMError.invalidConfig("unknown provider: \(provider)")
    }
    switch resolved {
    case .openai:
      guard let openai else { throw LLMError.invalidConfig("openai config required") }
      try openai.validate()
    case .anthropic:
      guard let anthropic else { throw LLMError.invalidConfig("anthropic config required") }
      try anthropic.validate()
    }
  }
}

extension LLMConfig {
  /// Builds the configured ``LLMProvider``, the analogue of Go's `ProvideLLMProvider(cfg, logger,
  /// tracerProvider, metricsProvider)`.
  ///
  /// Selects on ``provider``: a recognized backend yields its live provider (whose config must be present —
  /// validated here so a misconfiguration surfaces as a thrown ``LLMError`` rather than a runtime 401),
  /// while an empty or unrecognized value falls back to ``NoopLLMProvider``, matching Go's `default` case.
  public func provideLLMProvider(pillars: Pillars) throws -> any LLMProvider {
    switch resolvedProvider {
    case .openai:
      guard let openai else { throw LLMError.invalidConfig("openai config required") }
      try openai.validate()
      return OpenAIProvider(config: openai, pillars: pillars)
    case .anthropic:
      guard let anthropic else { throw LLMError.invalidConfig("anthropic config required") }
      try anthropic.validate()
      return AnthropicProvider(config: anthropic, pillars: pillars)
    case nil:
      return NoopLLMProvider()
    }
  }
}
