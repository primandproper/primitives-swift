import Observability

/// The recognized ``TextSearcher`` backends, ported from the `ElasticsearchProvider`/`AlgoliaProvider`
/// string constants in platform-go's `search/text/config` (package `textsearchcfg`) — replaced by the one
/// native backend this port keeps, ``sqlite`` (FTS5). See ``Search``.
public enum TextSearchProviderKind: String, Codable, Sendable, CaseIterable {
  /// The native SQLite FTS5 backend, ``SQLiteTextSearcher``. Accepts the alias `"fts5"` too (see
  /// ``TextSearchConfig/resolvedProvider``).
  case sqlite
}

/// Dispatch configuration for the text-search seam, ported from platform-go's `textsearchcfg.Config`:
/// ```go
/// type Config struct {
///     Algolia        *algolia.Config
///     Elasticsearch  *elasticsearch.Config
///     Provider       string
///     CircuitBreaker circuitbreakingcfg.Config
/// }
/// ```
/// narrowed to the native backend this port keeps. Go's `algolia`/`elasticsearch`/`circuitBreakerConfig`
/// keys are dropped (those remote backends have no iOS analogue — see ``Search``); a Go-authored payload
/// carrying them simply decode-and-ignores (`Codable` skips unrecognized keys), so wire compatibility
/// holds. Lenient `Codable`: `{}` decodes to an empty ``provider`` (→ noop), matching Go's `ProvideIndex`
/// `default` case.
public struct TextSearchConfig: Codable, Sendable, Equatable {
  /// Selects the backend. Empty or unrecognized resolves to ``NoopTextSearcher``, exactly like Go's
  /// `ProvideIndex` `default`. Recognized: `sqlite` (or its alias `fts5`).
  public var provider: String
  /// The FTS5 table / index name passed to ``SQLiteTextSearcher/init(path:indexName:name:pillars:)``.
  /// Empty resolves to that initializer's default.
  public var indexName: String
  /// SQLite database file path. Empty (the default) uses a private in-memory database.
  public var path: String

  public init(provider: String = "", indexName: String = "", path: String = "") {
    self.provider = provider
    self.indexName = indexName
    self.path = path
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case indexName
    case path
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    indexName = try c.decodeIfPresent(String.self, forKey: .indexName) ?? ""
    path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if !provider.isEmpty { try c.encode(provider, forKey: .provider) }
    if !indexName.isEmpty { try c.encode(indexName, forKey: .indexName) }
    if !path.isEmpty { try c.encode(path, forKey: .path) }
  }

  /// The recognized ``TextSearchProviderKind`` ``provider`` resolves to, or `nil` for an empty/unknown
  /// value (→ noop). Canonicalizes with trim+lowercase like Go's `ValidateWithContext`, and accepts
  /// `"fts5"` as an alias for ``TextSearchProviderKind/sqlite``.
  public var resolvedProvider: TextSearchProviderKind? {
    switch provider.trimmingCharacters(in: .whitespaces).lowercased() {
    case "sqlite", "fts5": return .sqlite
    default: return nil
    }
  }

  /// Builds the configured ``TextSearcher``, the analogue of Go's `ProvideIndex[T]`. A recognized backend
  /// yields its live searcher (throwing if construction fails — e.g. an invalid index name, or a system
  /// SQLite lacking FTS5); an empty or unrecognized ``provider`` falls back to ``NoopTextSearcher``,
  /// matching Go's `default` case.
  public func provideTextSearcher(pillars: Pillars) throws -> any TextSearcher {
    switch resolvedProvider {
    case .sqlite:
      return try SQLiteTextSearcher(
        path: path,
        indexName: indexName.isEmpty ? "search_documents" : indexName,
        pillars: pillars)
    case nil:
      return NoopTextSearcher()
    }
  }
}
