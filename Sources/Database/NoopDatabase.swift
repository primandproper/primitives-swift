/// A no-op ``Database``. The always-safe fallback for a "no database configured" path: migrations report
/// version `0`, executes affect nothing, and queries return no rows — so callers need not nil-check a
/// database that may not exist. The analogue of the `Noop` doubles every protocol-bearing module in this
/// port ships.
public struct NoopDatabase: Database {
  public init() {}

  @discardableResult
  public func migrate(_ migrations: [Migration]) async throws -> Int { 0 }

  public func currentVersion() async throws -> Int { 0 }

  @discardableResult
  public func execute(_ sql: String, _ parameters: [SQLValue]) async throws -> ExecResult {
    ExecResult(rowsAffected: 0, lastInsertRowID: 0)
  }

  public func query(_ sql: String, _ parameters: [SQLValue]) async throws -> [Row] { [] }

  public func close() async {}
}
