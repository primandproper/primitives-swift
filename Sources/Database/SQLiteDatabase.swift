import DurationWire
import Foundation
import Observability
import SQLite3

// SQLite's `SQLITE_TRANSIENT` sentinel tells the C API to copy a bound value immediately, so the Swift
// buffer we bind from only needs to stay valid for the duration of the bind call. It is a C macro
// (`(sqlite3_destructor_type)(-1)`) with no imported symbol, so it is reconstructed here — the same idiom
// as `Sources/Search`'s FTS5 searcher.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The live ``Database``, backed by a single local SQLite connection reached through the system `SQLite3`
/// C library. This is the iOS client adaptation of platform-go's `database/sqlite` client, minus the
/// read/write pool split (one local file needs no pool) and the otelsql plumbing.
///
/// An `actor` provides the mutual exclusion a single SQLite connection needs without hand-rolled locks —
/// the same choice `Sources/Search`'s `SQLiteTextSearcher` and `Sources/Cache`'s in-memory cache make.
/// An injected ``Observability/Pillars`` threads through: each operation opens a span via a
/// ``Observability/LiveObserver`` and emits `_requests` / `_errors` counters plus a `_latency_ms`
/// histogram under ``metricName``.
public actor SQLiteDatabase: Database {
  /// Default observability/metric prefix. Metrics emit as `database_requests` / `database_errors` /
  /// `database_latency_ms`.
  public static let defaultName = "database"

  /// The bookkeeping table the migration runner records applied versions in.
  static let migrationsTable = "schema_migrations"

  /// Owns the SQLite connection handle and closes it on release. Wrapping the non-`Sendable`
  /// `OpaquePointer` in an `@unchecked Sendable` box (whose `deinit` closes the handle) sidesteps Swift
  /// 6's ban on touching non-`Sendable` state from an actor's nonisolated `deinit`. The same idiom as
  /// `SQLiteTextSearcher.ConnectionBox`.
  private final class ConnectionBox: @unchecked Sendable {
    let db: OpaquePointer
    private(set) var closed = false
    init(_ db: OpaquePointer) { self.db = db }
    func close() {
      guard !closed else { return }
      sqlite3_close(db)
      closed = true
    }
    deinit { close() }
  }

  private let connection: ConnectionBox
  private var db: OpaquePointer { connection.db }
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let metricName: String

  /// Opens the database described by `config` and applies its PRAGMA settings.
  ///
  /// - Parameters:
  ///   - config: where the file lives and the per-connection knobs. An empty/in-memory path opens a
  ///     private `:memory:` database.
  ///   - name: observability/metric prefix. Defaults to ``defaultName``.
  ///   - pillars: observability pillars; side effects open spans/metrics through these. Defaults to
  ///     ``Observability/Pillars/noop``.
  public init(
    config: DatabaseConfig,
    name: String = SQLiteDatabase.defaultName,
    pillars: Pillars = .noop
  ) throws {
    self.metricName = name
    let observer = LiveObserver(name: name, logger: pillars.logger, tracer: pillars.tracer)
    self.observer = observer
    self.metrics = pillars.metrics

    let op = observer.begin("db.open")
    defer { op.end() }

    let filename = config.resolvedPath()
    op.set("db.system", "sqlite")
    op.set("db.path", filename)

    var handle: OpaquePointer?
    guard sqlite3_open(filename, &handle) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
      sqlite3_close(handle)
      op.acknowledge(DatabaseError.open(message), "opening database")
      throw DatabaseError.open(message)
    }
    self.connection = ConnectionBox(handle)

    do {
      try Self.applyPragmas(db: handle, config: config)
    } catch {
      op.acknowledge(error, "applying pragmas")
      throw error
    }
    op.logger.info("database opened")
  }

  // MARK: - Pragmas

  private static func applyPragmas(db: OpaquePointer, config: DatabaseConfig) throws {
    if config.foreignKeys {
      try exec(db: db, "PRAGMA foreign_keys = ON;")
    }
    // busy_timeout takes whole milliseconds; clamp negatives to 0 (no wait).
    let millis = max(config.busyTimeout.wholeMilliseconds, 0)
    try exec(db: db, "PRAGMA busy_timeout = \(millis);")
    // WAL is persisted in the file and meaningless for :memory:, so only set it for on-disk databases.
    if config.walJournalMode && config.resolvedPath() != ":memory:" {
      try exec(db: db, "PRAGMA journal_mode = WAL;")
    }
  }

  // MARK: - Query surface

  @discardableResult
  public func execute(_ sql: String, _ parameters: [SQLValue] = []) async throws -> ExecResult {
    let op = observer.begin("db.execute")
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }
    do {
      try Self.run(db: db, sql, parameters)
      let result = ExecResult(
        rowsAffected: Int(sqlite3_changes(db)),
        lastInsertRowID: sqlite3_last_insert_rowid(db))
      metrics.counter("\(metricName)_requests").increment()
      return result
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "execute failed")
      throw error
    }
  }

  public func query(_ sql: String, _ parameters: [SQLValue] = []) async throws -> [Row] {
    let op = observer.begin("db.query")
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }
    do {
      var rows: [Row] = []
      try Self.run(db: db, sql, parameters) { stmt in rows.append(Self.readRow(stmt)) }
      metrics.counter("\(metricName)_requests").increment()
      op.set("db.rows", rows.count)
      return rows
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "query failed")
      throw error
    }
  }

  public func close() async {
    connection.close()
  }

  // MARK: - Migration runner

  @discardableResult
  public func migrate(_ migrations: [Migration]) async throws -> Int {
    let op = observer.begin("db.migrate")
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }
    do {
      try Self.exec(
        db: db,
        "CREATE TABLE IF NOT EXISTS \(Self.migrationsTable) "
          + "(version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at TEXT NOT NULL);")

      var version = try Self.readVersion(db: db)
      op.set("db.migration.start_version", version)

      // Apply in ascending order; each pending migration runs inside its own transaction so a failure
      // leaves the schema at the last fully-applied version rather than half-migrated.
      for migration in migrations.sorted(by: { $0.version < $1.version })
      where migration.version > version {
        try Self.applyMigration(db: db, migration)
        version = migration.version
      }

      op.set("db.migration.end_version", version)
      metrics.counter("\(metricName)_requests").increment()
      return version
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "migrate failed")
      throw error
    }
  }

  public func currentVersion() async throws -> Int {
    // No migrations table yet means nothing has been applied.
    guard try Self.tableExists(db: db, Self.migrationsTable) else { return 0 }
    return try Self.readVersion(db: db)
  }

  private static func applyMigration(db: OpaquePointer, _ migration: Migration) throws {
    try exec(db: db, "BEGIN;")
    do {
      try exec(db: db, migration.sql)
      try run(
        db: db,
        "INSERT INTO \(migrationsTable) (version, name, applied_at) VALUES (?, ?, ?);",
        [
          .integer(Int64(migration.version)),
          .text(migration.name),
          .text(ISO8601DateFormatter().string(from: Date())),
        ])
      try exec(db: db, "COMMIT;")
    } catch {
      // Roll back so the failed migration leaves no partial schema change behind.
      try? exec(db: db, "ROLLBACK;")
      let message = (error as? DatabaseError).map { $0.description } ?? "\(error)"
      throw DatabaseError.migration("version \(migration.version): \(message)")
    }
  }

  private static func readVersion(db: OpaquePointer) throws -> Int {
    var version = 0
    try run(db: db, "SELECT COALESCE(MAX(version), 0) FROM \(migrationsTable);") { stmt in
      version = Int(sqlite3_column_int64(stmt, 0))
    }
    return version
  }

  private static func tableExists(db: OpaquePointer, _ name: String) throws -> Bool {
    var found = false
    try run(
      db: db,
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;",
      [.text(name)]
    ) { _ in found = true }
    return found
  }

  // MARK: - SQLite plumbing

  /// Runs a script of one or more `;`-separated statements with no bound parameters and no result rows,
  /// via `sqlite3_exec`. Used for DDL and transaction control.
  private static func exec(db: OpaquePointer, _ sql: String) throws {
    var err: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
      let message = err.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
      sqlite3_free(err)
      throw DatabaseError.backend(message)
    }
  }

  /// Prepares `sql`, binds `parameters` positionally, then steps to completion. When `eachRow` is
  /// supplied it is invoked for every result row. Finalizes the statement on every path.
  private static func run(
    db: OpaquePointer,
    _ sql: String,
    _ parameters: [SQLValue] = [],
    _ eachRow: ((OpaquePointer?) -> Void)? = nil
  ) throws {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      let message = String(cString: sqlite3_errmsg(db))
      sqlite3_finalize(stmt)
      throw DatabaseError.backend(message)
    }
    defer { sqlite3_finalize(stmt) }

    bind(stmt, parameters)

    if let eachRow {
      var status = sqlite3_step(stmt)
      while status == SQLITE_ROW {
        eachRow(stmt)
        status = sqlite3_step(stmt)
      }
      guard status == SQLITE_DONE else {
        throw DatabaseError.backend(String(cString: sqlite3_errmsg(db)))
      }
    } else {
      guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw DatabaseError.backend(String(cString: sqlite3_errmsg(db)))
      }
    }
  }

  private static func bind(_ stmt: OpaquePointer?, _ parameters: [SQLValue]) {
    for (offset, value) in parameters.enumerated() {
      let index = Int32(offset + 1)
      switch value {
      case .null:
        sqlite3_bind_null(stmt, index)
      case .integer(let int):
        sqlite3_bind_int64(stmt, index, int)
      case .real(let double):
        sqlite3_bind_double(stmt, index, double)
      case .text(let string):
        _ = string.withCString { sqlite3_bind_text(stmt, index, $0, -1, sqliteTransient) }
      case .blob(let bytes):
        if bytes.isEmpty {
          sqlite3_bind_zeroblob(stmt, index, 0)
        } else {
          _ = bytes.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(bytes.count), sqliteTransient)
          }
        }
      }
    }
  }

  private static func readRow(_ stmt: OpaquePointer?) -> Row {
    let count = sqlite3_column_count(stmt)
    var columns: [String] = []
    var values: [SQLValue] = []
    columns.reserveCapacity(Int(count))
    values.reserveCapacity(Int(count))
    for column in 0..<count {
      columns.append(String(cString: sqlite3_column_name(stmt, column)))
      switch sqlite3_column_type(stmt, column) {
      case SQLITE_INTEGER:
        values.append(.integer(sqlite3_column_int64(stmt, column)))
      case SQLITE_FLOAT:
        values.append(.real(sqlite3_column_double(stmt, column)))
      case SQLITE_TEXT:
        values.append(.text(String(cString: sqlite3_column_text(stmt, column))))
      case SQLITE_BLOB:
        let length = Int(sqlite3_column_bytes(stmt, column))
        if let pointer = sqlite3_column_blob(stmt, column), length > 0 {
          let buffer = UnsafeRawBufferPointer(start: pointer, count: length)
          values.append(.blob([UInt8](buffer)))
        } else {
          values.append(.blob([]))
        }
      default:
        values.append(.null)
      }
    }
    return Row(columns: columns, values: values)
  }

  private func recordLatency(since start: ContinuousClock.Instant) {
    metrics.histogram("\(metricName)_latency_ms").record(
      Double(start.duration(to: .now).wholeNanoseconds) / 1_000_000)
  }
}
