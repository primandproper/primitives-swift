/// A test double for ``VectorSearcher``, ported from platform-go's moq-generated `mock.IndexMock`
/// (`search/vector/mock/index_mock.go`).
///
/// Go's moq output is a struct with `UpsertFunc`/`DeleteFunc`/`WipeFunc`/`QueryFunc` fields plus
/// mutex-guarded call recording; calling a method whose `*Func` is unset panics. The Swift port keeps the
/// shape — optional handler closures plus recorded-calls lists — but trades panic-on-unset for a quieter
/// default matching ``NoopVectorSearcher`` (empty results, silent writes). Thread safety comes from this
/// being an `actor`, matching `Sources/LLM`'s `LLMProviderMock`.
///
/// Because handlers are `public var` on an actor (which Swift 6 forbids assigning cross-actor), each has a
/// `set…Handler` mutator — the supported way to script the double post-init (REPO-05).
public actor VectorSearcherMock: VectorSearcher {
  public var upsertHandler: (@Sendable ([VectorRecord]) async throws -> Void)?
  public var deleteHandler: (@Sendable ([String]) async throws -> Void)?
  public var wipeHandler: (@Sendable () async throws -> Void)?
  public var queryHandler: (@Sendable (VectorQuery) async throws -> [VectorSearchResult])?

  public private(set) var upsertCalls: [[VectorRecord]] = []
  public private(set) var deleteCalls: [[String]] = []
  public private(set) var wipeCalls: Int = 0
  public private(set) var queryCalls: [VectorQuery] = []

  public init(
    upsertHandler: (@Sendable ([VectorRecord]) async throws -> Void)? = nil,
    deleteHandler: (@Sendable ([String]) async throws -> Void)? = nil,
    wipeHandler: (@Sendable () async throws -> Void)? = nil,
    queryHandler: (@Sendable (VectorQuery) async throws -> [VectorSearchResult])? = nil
  ) {
    self.upsertHandler = upsertHandler
    self.deleteHandler = deleteHandler
    self.wipeHandler = wipeHandler
    self.queryHandler = queryHandler
  }

  public func setUpsertHandler(_ handler: (@Sendable ([VectorRecord]) async throws -> Void)?) {
    upsertHandler = handler
  }

  public func setDeleteHandler(_ handler: (@Sendable ([String]) async throws -> Void)?) {
    deleteHandler = handler
  }

  public func setWipeHandler(_ handler: (@Sendable () async throws -> Void)?) {
    wipeHandler = handler
  }

  public func setQueryHandler(
    _ handler: (@Sendable (VectorQuery) async throws -> [VectorSearchResult])?
  ) {
    queryHandler = handler
  }

  public func upsert(_ records: [VectorRecord]) async throws {
    upsertCalls.append(records)
    try await upsertHandler?(records)
  }

  public func delete(ids: [String]) async throws {
    deleteCalls.append(ids)
    try await deleteHandler?(ids)
  }

  public func wipe() async throws {
    wipeCalls += 1
    try await wipeHandler?()
  }

  public func query(_ request: VectorQuery) async throws -> [VectorSearchResult] {
    queryCalls.append(request)
    if let queryHandler {
      return try await queryHandler(request)
    }
    return []
  }
}
