/// A no-op ``TextSearcher``, ported from platform-go's `search/text/noop`. The safe default when no text
/// backend is configured (or an unrecognized one is): searches return an empty result set and writes
/// silently succeed, so a caller never has to nil-check an index that may not exist. Mirrors Go's
/// `noop.indexManager` returning `[]*T{}, nil` from `Search` and `nil` from the write methods.
public struct NoopTextSearcher: TextSearcher {
  public init() {}

  public func index(_ document: TextDocument) async throws {}

  public func search(_ query: String, limit: Int) async throws -> [TextSearchResult] {
    []
  }

  public func delete(id: String) async throws {}

  public func wipe() async throws {}
}
