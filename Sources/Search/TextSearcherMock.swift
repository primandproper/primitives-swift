/// A test double for ``TextSearcher``, ported from platform-go's moq-generated `mocksearch.IndexMock`
/// (`search/text/mock/index_mock.go`).
///
/// Go's moq output is a struct with `IndexFunc`/`SearchFunc`/`DeleteFunc`/`WipeFunc` fields plus
/// mutex-guarded call recording; calling a method whose `*Func` is unset panics. The Swift port keeps the
/// shape — optional handler closures plus recorded-calls lists — but trades panic-on-unset for a quieter
/// default matching ``NoopTextSearcher`` (empty results, silent writes). Thread safety comes from this
/// being an `actor`, matching `Sources/LLM`'s `LLMProviderMock`.
///
/// Because handlers are `public var` on an actor (which Swift 6 forbids assigning cross-actor), each has a
/// `set…Handler` mutator — the supported way to script the double post-init (REPO-05).
public actor TextSearcherMock: TextSearcher {
  public var indexHandler: (@Sendable (TextDocument) async throws -> Void)?
  public var searchHandler: (@Sendable (String, Int) async throws -> [TextSearchResult])?
  public var deleteHandler: (@Sendable (String) async throws -> Void)?
  public var wipeHandler: (@Sendable () async throws -> Void)?

  public private(set) var indexCalls: [TextDocument] = []
  public private(set) var searchCalls: [(query: String, limit: Int)] = []
  public private(set) var deleteCalls: [String] = []
  public private(set) var wipeCalls: Int = 0

  public init(
    indexHandler: (@Sendable (TextDocument) async throws -> Void)? = nil,
    searchHandler: (@Sendable (String, Int) async throws -> [TextSearchResult])? = nil,
    deleteHandler: (@Sendable (String) async throws -> Void)? = nil,
    wipeHandler: (@Sendable () async throws -> Void)? = nil
  ) {
    self.indexHandler = indexHandler
    self.searchHandler = searchHandler
    self.deleteHandler = deleteHandler
    self.wipeHandler = wipeHandler
  }

  public func setIndexHandler(_ handler: (@Sendable (TextDocument) async throws -> Void)?) {
    indexHandler = handler
  }

  public func setSearchHandler(
    _ handler: (@Sendable (String, Int) async throws -> [TextSearchResult])?
  ) {
    searchHandler = handler
  }

  public func setDeleteHandler(_ handler: (@Sendable (String) async throws -> Void)?) {
    deleteHandler = handler
  }

  public func setWipeHandler(_ handler: (@Sendable () async throws -> Void)?) {
    wipeHandler = handler
  }

  public func index(_ document: TextDocument) async throws {
    indexCalls.append(document)
    try await indexHandler?(document)
  }

  public func search(_ query: String, limit: Int) async throws -> [TextSearchResult] {
    searchCalls.append((query, limit))
    if let searchHandler {
      return try await searchHandler(query, limit)
    }
    return []
  }

  public func delete(id: String) async throws {
    deleteCalls.append(id)
    try await deleteHandler?(id)
  }

  public func wipe() async throws {
    wipeCalls += 1
    try await wipeHandler?()
  }
}
