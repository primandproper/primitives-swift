import Foundation

/// Errors surfaced by the ``TextSearcher`` and ``VectorSearcher`` conformers, ported from the sentinel
/// error family in platform-go's `search/vector/vector.go` (`ErrEmptyEmbedding`, `ErrNotFound`,
/// `ErrNilConfig`, `ErrDimensionMismatch`, `ErrInvalidMetric`, `ErrInvalidDimension`) plus the native
/// backends' own failures.
///
/// Go's text package leans on plain wrapped errors from its Elasticsearch/Algolia clients; those backends
/// are dropped here (see ``Search``), so the only text-side failure this port raises is ``backend(_:)``
/// wrapping a message from the SQLite C API. The vector-side cases mirror Go's sentinels one-for-one, as
/// `Equatable` cases so a caller can `switch`/`catch` on them the way Go compares with `errors.Is`.
public enum SearchError: Error, Equatable, Sendable {
  /// A query or upsert was attempted with a zero-length vector. Mirrors Go's `ErrEmptyEmbedding`.
  case emptyEmbedding
  /// An embedding's dimension does not match the index's configured dimension. Mirrors Go's
  /// `ErrDimensionMismatch`; carries both widths for a precise message.
  case dimensionMismatch(expected: Int, actual: Int)
  /// A non-positive index dimension was configured. Mirrors Go's `ErrInvalidDimension`.
  case invalidDimension(Int)
  /// An unsupported ``VectorDistanceMetric`` string was configured. Mirrors Go's `ErrInvalidMetric`.
  case invalidMetric(String)
  /// A record/document with the given ID does not exist. Mirrors Go's `ErrNotFound`. (The native indexes
  /// treat delete-of-missing as a silent no-op, matching Go's providers; this case exists for adapters
  /// and lookups that need to distinguish it.)
  case notFound(String)
  /// The config failed validation, or a construction precondition (e.g. an unknown provider, an invalid
  /// index name). Subsumes Go's `ErrNilConfig`. Carries the human-readable reason.
  case invalidConfig(String)
  /// The underlying storage engine (the SQLite C library, for ``SQLiteTextSearcher``) reported a failure.
  /// Carries the engine's message.
  case backend(String)

  public var description: String {
    switch self {
    case .emptyEmbedding: return "empty embedding vector provided"
    case .dimensionMismatch(let expected, let actual):
      return "embedding dimension \(actual) does not match index dimension \(expected)"
    case .invalidDimension(let dimension): return "invalid index dimension: \(dimension)"
    case .invalidMetric(let metric): return "invalid distance metric: \(metric)"
    case .notFound(let id): return "not found: \(id)"
    case .invalidConfig(let reason): return "invalid search config: \(reason)"
    case .backend(let message): return "search backend error: \(message)"
    }
  }
}

extension SearchError: LocalizedError {
  public var errorDescription: String? { description }
}
