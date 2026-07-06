/// A recording test double for ``Database``, adapted from platform-go's moq-generated
/// `mockdatabase.ClientMock`.
///
/// Go's moq output is a struct of `*Func` handler fields plus mutex-guarded call slices, where calling a
/// method whose handler is unset panics. The Swift port keeps the record-and-delegate shape but is an
/// `actor` for thread safety (matching ``LLM/LLMProviderMock``) and trades panic-on-unset for a quiet
/// default: an unset handler returns an empty result. Per Swift-6 actor-safety, handlers are immutable
/// `let` closures supplied at construction (not cross-actor `var`s); the recorded call lists are
/// `private(set)` and read back through the actor.
public actor MockDatabase: Database {
  /// A recorded ``execute(_:_:)`` / ``query(_:_:)`` invocation.
  public struct Call: Sendable, Equatable {
    public let sql: String
    public let parameters: [SQLValue]
    public init(sql: String, parameters: [SQLValue]) {
      self.sql = sql
      self.parameters = parameters
    }
  }

  public private(set) var executeCalls: [Call] = []
  public private(set) var queryCalls: [Call] = []
  public private(set) var migrateCalls: [[Migration]] = []
  public private(set) var currentVersionCallCount = 0
  public private(set) var closeCallCount = 0

  private let executeHandler: (@Sendable (String, [SQLValue]) async throws -> ExecResult)?
  private let queryHandler: (@Sendable (String, [SQLValue]) async throws -> [Row])?
  private let migrateHandler: (@Sendable ([Migration]) async throws -> Int)?
  private let currentVersionHandler: (@Sendable () async throws -> Int)?

  public init(
    executeHandler: (@Sendable (String, [SQLValue]) async throws -> ExecResult)? = nil,
    queryHandler: (@Sendable (String, [SQLValue]) async throws -> [Row])? = nil,
    migrateHandler: (@Sendable ([Migration]) async throws -> Int)? = nil,
    currentVersionHandler: (@Sendable () async throws -> Int)? = nil
  ) {
    self.executeHandler = executeHandler
    self.queryHandler = queryHandler
    self.migrateHandler = migrateHandler
    self.currentVersionHandler = currentVersionHandler
  }

  @discardableResult
  public func migrate(_ migrations: [Migration]) async throws -> Int {
    migrateCalls.append(migrations)
    if let migrateHandler { return try await migrateHandler(migrations) }
    return 0
  }

  public func currentVersion() async throws -> Int {
    currentVersionCallCount += 1
    if let currentVersionHandler { return try await currentVersionHandler() }
    return 0
  }

  @discardableResult
  public func execute(_ sql: String, _ parameters: [SQLValue]) async throws -> ExecResult {
    executeCalls.append(Call(sql: sql, parameters: parameters))
    if let executeHandler { return try await executeHandler(sql, parameters) }
    return ExecResult(rowsAffected: 0, lastInsertRowID: 0)
  }

  public func query(_ sql: String, _ parameters: [SQLValue]) async throws -> [Row] {
    queryCalls.append(Call(sql: sql, parameters: parameters))
    if let queryHandler { return try await queryHandler(sql, parameters) }
    return []
  }

  public func close() async {
    closeCallCount += 1
  }
}
