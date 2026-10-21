import Observability

/// The recognized ``Embedder`` backends. Go's `embeddings/config/config.go` (package `embeddingscfg`)
/// declares `ProviderOpenAI`/`ProviderOllama`/`ProviderCohere`; every one of those is a remote API this
/// port drops (see ``Embeddings``), leaving only ``onDevice``, a new value with no Go analogue.
///
/// Go validates its `Config.Provider` as a bare string with `validation.In(ProviderOpenAI,
/// ProviderOllama, ProviderCohere, "")`, resolving an empty/unknown value to the noop embedder.
/// ``EmbeddingsConfig/provider`` keeps that raw-string shape for that lenient fallback; this closed enum
/// is what a recognized string resolves into.
public enum EmbeddingsProviderKind: String, Codable, Sendable, CaseIterable {
  case onDevice = "ondevice"
}

/// The top-level embeddings configuration, ported from platform-go's `embeddingscfg.Config`:
/// ```go
/// type Config struct {
///     OpenAI   *openai.Config `json:"openai"`
///     Ollama   *ollama.Config `json:"ollama"`
///     Cohere   *cohere.Config `json:"cohere"`
///     Provider string         `json:"provider"`
/// }
/// ```
/// narrowed to the one backend this port keeps (``onDevice``) — `openai`/`ollama`/`cohere` are dropped
/// per ``Embeddings``'s port rationale, so a Go-authored payload's `openai`/`ollama`/`cohere` keys simply
/// decode-and-ignore rather than being rejected (`Codable` skips unrecognized keys).
///
/// ``provider`` selects the backend: empty or unrecognized resolves to a noop, exactly like Go's
/// `ProvideEmbedder` `default` case. Wire keys: `onDevice`, `provider`.
public struct EmbeddingsConfig: Codable, Sendable, Equatable {
  public var onDevice: OnDeviceEmbedderConfig?
  public var provider: String

  public init(
    onDevice: OnDeviceEmbedderConfig? = nil,
    provider: String = ""
  ) {
    self.onDevice = onDevice
    self.provider = provider
  }

  private enum CodingKeys: String, CodingKey {
    case onDevice
    case provider
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    onDevice = try c.decodeIfPresent(OnDeviceEmbedderConfig.self, forKey: .onDevice)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
  }

  /// The recognized ``EmbeddingsProviderKind`` ``provider`` resolves to, or `nil` for an empty/unknown
  /// value (→ noop). The analogue of Go's lowercase/trim before the switch in `ProvideEmbedder`.
  public var resolvedProvider: EmbeddingsProviderKind? {
    EmbeddingsProviderKind(rawValue: provider.trimmingCharacters(in: .whitespaces).lowercased())
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`. An unrecognized ``provider`` is
  /// rejected; ``onDevice`` accepts any value, including `nil`, since ``OnDeviceEmbedderConfig`` has no
  /// required fields; an empty ``provider`` (noop) is allowed with no provider config.
  public func validate() throws {
    let trimmed = provider.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return }
    guard let resolved = resolvedProvider else {
      throw EmbeddingsError.invalidConfig("unknown provider: \(provider)")
    }
    switch resolved {
    case .onDevice:
      break
    }
  }

  /// Builds the configured ``Embedder``, the analogue of Go's `ProvideEmbedder(ctx, cfg, logger, tracer)`.
  ///
  /// Selects on ``provider``: a recognized backend yields its live embedder (throwing if that backend's
  /// construction fails — no on-device model for the requested language), while an empty or
  /// unrecognized value falls back to ``NoopEmbedder``, matching Go's `default` case. `pillars` is unused
  /// by the on-device backend but keeps the `provide…(pillars:)` shape every config in this package shares.
  public func provideEmbedder(pillars: Pillars) throws -> any Embedder {
    switch resolvedProvider {
    case .onDevice:
      return try OnDeviceEmbedder(config: onDevice ?? OnDeviceEmbedderConfig())
    case nil:
      return NoopEmbedder()
    }
  }
}
