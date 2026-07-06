import Foundation

/// The outcome of a non-`SELECT` statement, the port's replacement for Go's `sql.Result`.
public struct ExecResult: Sendable, Equatable {
  /// Rows inserted, updated, or deleted by the statement (`sqlite3_changes`).
  public let rowsAffected: Int
  /// The rowid of the most recent successful INSERT on this connection (`sqlite3_last_insert_rowid`).
  public let lastInsertRowID: Int64

  public init(rowsAffected: Int, lastInsertRowID: Int64) {
    self.rowsAffected = rowsAffected
    self.lastInsertRowID = lastInsertRowID
  }
}

/// The typed access seam over a local SQLite database — the iOS client adaptation of platform-go's
/// `database.Client` + `database.SQLQueryExecutor`.
///
/// This is a deliberate *adaptation*, not a literal port. Dropped from the Go origin: the read/write
/// connection split (an iOS app talks to one local file), the admin `Manager` (create user / grant), and
/// the MySQL/Postgres backends. Kept: a versioned, idempotent ``migrate(_:)`` runner and a small
/// parameterized ``execute(_:_:)`` / ``query(_:_:)`` surface returning typed ``Row``s.
///
/// Every conformer is `Sendable`; the live implementation (``SQLiteDatabase``) is an `actor` giving the
/// single-connection mutual exclusion SQLite needs. A ``NoopDatabase`` and a ``MockDatabase`` ship for
/// tests and for the "no database configured" path.
public protocol Database: Sendable {
  /// Applies any migrations whose ``Migration/version`` exceeds the recorded schema version, in
  /// ascending order, each inside its own transaction, then returns the resulting schema version.
  /// Idempotent: already-applied migrations are skipped, so calling this on every launch is safe.
  @discardableResult
  func migrate(_ migrations: [Migration]) async throws -> Int

  /// The highest applied migration version, or `0` if none have been applied.
  func currentVersion() async throws -> Int

  /// Runs a non-`SELECT` statement with positional (`?`) parameters, returning the affected-row count
  /// and last insert rowid.
  @discardableResult
  func execute(_ sql: String, _ parameters: [SQLValue]) async throws -> ExecResult

  /// Runs a `SELECT` with positional (`?`) parameters, returning every result row.
  func query(_ sql: String, _ parameters: [SQLValue]) async throws -> [Row]

  /// Closes the underlying connection. Idempotent.
  func close() async
}

extension Database {
  /// Runs a parameterless non-`SELECT` statement.
  @discardableResult
  public func execute(_ sql: String) async throws -> ExecResult {
    try await execute(sql, [])
  }

  /// Runs a parameterless `SELECT`.
  public func query(_ sql: String) async throws -> [Row] {
    try await query(sql, [])
  }

  /// Runs a `SELECT` expected to yield at most one row, returning the first (or `nil`). The analogue of
  /// Go's `QueryRowContext`.
  public func queryOne(_ sql: String, _ parameters: [SQLValue] = []) async throws -> Row? {
    try await query(sql, parameters).first
  }
}
