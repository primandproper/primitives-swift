import Observability

/// The recognized ``VectorSearcher`` backends, ported from the `PGvectorProvider`/`QdrantProvider` string
/// constants in platform-go's `search/vector/config` (package `vectorsearchcfg`) — replaced by the one
/// native backend this port keeps, ``inMemory``. See ``Search``.
public enum VectorSearchProviderKind: String, Codable, Sendable, CaseIterable {
  /// The native brute-force backend, ``InMemoryVectorIndex``. Accepts the alias `"inmemory"` too (see
  /// ``VectorSearchConfig/resolvedProvider``).
  case inMemory = "memory"
}

/// Dispatch configuration for the vector-search seam, ported from platform-go's `vectorsearchcfg.Config`:
/// ```go
/// type Config struct {
///     Pgvector       *pgvector.Config
///     Qdrant         *qdrant.Config
///     Provider       string
///     CircuitBreaker circuitbreakingcfg.Config
/// }
/// ```
/// narrowed to the native backend this port keeps, plus the ``dimensions``/``metric`` an in-memory index
/// needs at construction (Go carries these inside each provider's own `Config`). Go's
/// `pgvector`/`qdrant`/`circuitBreakerConfig` keys are dropped (remote backends, no iOS analogue — see
/// ``Search``); a Go-authored payload carrying them decode-and-ignores. Lenient `Codable`: `{}` decodes to
/// an empty ``provider`` (→ noop), matching Go's `ProvideIndex` `default` case.
public struct VectorSearchConfig: Codable, Sendable, Equatable {
  /// Selects the backend. Empty or unrecognized resolves to ``NoopVectorSearcher``, exactly like Go's
  /// `ProvideIndex` `default`. Recognized: `memory` (or its alias `inmemory`).
  public var provider: String
  /// The fixed vector width for ``InMemoryVectorIndex``. Must be positive when ``provider`` selects the
  /// in-memory backend, else ``provideVectorSearcher(pillars:)`` throws.
  public var dimensions: Int
  /// The distance metric string (`cosine`/`dot`/`euclidean`). Empty or unrecognized resolves to
  /// ``VectorDistanceMetric/cosine``.
  public var metric: String

  public init(provider: String = "", dimensions: Int = 0, metric: String = "") {
    self.provider = provider
    self.dimensions = dimensions
    self.metric = metric
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case dimensions
    case metric
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    dimensions = try c.decodeIfPresent(Int.self, forKey: .dimensions) ?? 0
    metric = try c.decodeIfPresent(String.self, forKey: .metric) ?? ""
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if !provider.isEmpty { try c.encode(provider, forKey: .provider) }
    if dimensions != 0 { try c.encode(dimensions, forKey: .dimensions) }
    if !metric.isEmpty { try c.encode(metric, forKey: .metric) }
  }

  /// The recognized ``VectorSearchProviderKind`` ``provider`` resolves to, or `nil` for an empty/unknown
  /// value (→ noop). Canonicalizes with trim+lowercase, accepting `"inmemory"` as an alias for
  /// ``VectorSearchProviderKind/inMemory``.
  public var resolvedProvider: VectorSearchProviderKind? {
    switch provider.trimmingCharacters(in: .whitespaces).lowercased() {
    case "memory", "inmemory": return .inMemory
    default: return nil
    }
  }

  /// The recognized ``VectorDistanceMetric`` ``metric`` resolves to, defaulting to
  /// ``VectorDistanceMetric/cosine`` for an empty/unknown value.
  public var resolvedMetric: VectorDistanceMetric {
    VectorDistanceMetric(rawValue: metric.trimmingCharacters(in: .whitespaces).lowercased())
      ?? .cosine
  }

  /// Builds the configured ``VectorSearcher``, the analogue of Go's `ProvideIndex[T]`. The in-memory
  /// backend yields an ``InMemoryVectorIndex`` (throwing ``SearchError/invalidDimension(_:)`` if
  /// ``dimensions`` is non-positive); an empty or unrecognized ``provider`` falls back to
  /// ``NoopVectorSearcher``, matching Go's `default` case.
  public func provideVectorSearcher(pillars: Pillars) throws -> any VectorSearcher {
    switch resolvedProvider {
    case .inMemory:
      return try InMemoryVectorIndex(
        dimensions: dimensions, metric: resolvedMetric, pillars: pillars)
    case nil:
      return NoopVectorSearcher()
    }
  }
}
