/// A no-op ``VectorSearcher``, ported from platform-go's `search/vector/noop`. The safe default when no
/// vector backend is configured (or an unrecognized one is): queries return an empty result set and writes
/// silently succeed. Mirrors Go's `noop.indexManager` returning `[]QueryResult[T]{}, nil` from `Query` and
/// `nil` from the write methods.
public struct NoopVectorSearcher: VectorSearcher {
  public init() {}

  public func upsert(_ records: [VectorRecord]) async throws {}

  public func delete(ids: [String]) async throws {}

  public func wipe() async throws {}

  public func query(_ request: VectorQuery) async throws -> [VectorSearchResult] {
    []
  }
}
