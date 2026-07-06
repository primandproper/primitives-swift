import Foundation
import Observability
import SQLite3

// SQLite's `SQLITE_TRANSIENT` sentinel tells the C API to copy a bound value immediately, so the Swift
// buffer we bind from only needs to stay valid for the duration of the bind call (not until step). It is
// a macro in C (`(sqlite3_destructor_type)(-1)`) with no imported symbol, so it is reconstructed here.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A **native** ``TextSearcher`` backed by SQLite's FTS5 full-text virtual-table module, reached through
/// the system `SQLite3` C library. This is the iOS-native replacement for Go's dropped Elasticsearch and
/// Algolia backends (see ``Search``): FTS5 gives real tokenized full-text ranking (`bm25`) with zero
/// server, and because it runs against an in-memory database it is fully unit-testable in-process.
///
/// An `actor` provides the mutual exclusion SQLite needs (a single connection is not safe to touch from
/// multiple threads concurrently) without hand-rolled locks, matching how `Sources/Cache`'s
/// `InMemoryCache` guards its map. Observability threads through an injected ``Observability/Pillars``
/// (SVC-10): each operation opens a span via a ``LiveObserver`` and emits `_requests`/`_errors` counters
/// plus a `_latency_ms` histogram under ``metricName``.
///
/// Ranking note: the FTS5 MATCH expression ORs the query's terms, so a document matching more of them
/// scores higher (`bm25` rewards term frequency and rarity); results come back most-relevant-first.
public actor SQLiteTextSearcher: TextSearcher {
  /// Default observability/metric prefix. Metrics emit as `sqlite_text_search_requests` /
  /// `sqlite_text_search_errors` / `sqlite_text_search_latency_ms`.
  public static let defaultName = "sqlite_text_search"

  /// Owns the SQLite connection handle and closes it on release. Wrapping the non-`Sendable`
  /// `OpaquePointer` in an `@unchecked Sendable` box (whose own `deinit` does the close) sidesteps Swift
  /// 6's ban on touching non-`Sendable` state from an actor's nonisolated `deinit`: the actor just holds a
  /// `Sendable` box, and cleanup rides the box's lifetime.
  private final class ConnectionBox: @unchecked Sendable {
    let db: OpaquePointer
    init(_ db: OpaquePointer) { self.db = db }
    deinit { sqlite3_close(db) }
  }

  private let connection: ConnectionBox
  private var db: OpaquePointer { connection.db }
  private let table: String
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let metricName: String

  /// Maps a document's string ``TextDocument/id`` to its FTS5 `rowid`, so an update (re-index) or delete
  /// can target the exact row without relying on FTS5's DELETE-by-column semantics.
  private var rowIDs: [String: Int64] = [:]

  /// - Parameters:
  ///   - path: SQLite database file path. Empty (the default) opens a private in-memory database — ideal
  ///     for a rebuild-on-launch index and for tests. A file path persists the index across launches.
  ///   - indexName: the FTS5 table name. Must be a valid SQL identifier (letters, digits, underscores;
  ///     not starting with a digit) or ``init`` throws ``SearchError/invalidConfig(_:)`` — it is
  ///     interpolated into DDL, so it is validated rather than escaped.
  ///   - name: observability/metric prefix. Defaults to ``defaultName``.
  ///   - pillars: observability pillars; side effects open spans/metrics through these. Defaults to
  ///     ``Observability/Pillars/noop``.
  public init(
    path: String = "",
    indexName: String = "search_documents",
    name: String = SQLiteTextSearcher.defaultName,
    pillars: Pillars = .noop
  ) throws {
    guard SQLiteTextSearcher.isValidIdentifier(indexName) else {
      throw SearchError.invalidConfig("invalid index name: \(indexName)")
    }
    self.table = indexName
    self.metricName = name
    self.observer = LiveObserver(name: name, logger: pillars.logger, tracer: pillars.tracer)
    self.metrics = pillars.metrics

    var handle: OpaquePointer?
    let filename = path.isEmpty ? ":memory:" : path
    guard sqlite3_open(filename, &handle) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
      sqlite3_close(handle)
      throw SearchError.backend(message)
    }
    self.connection = ConnectionBox(handle)

    // A regular (not external-content) FTS5 table: `doc_id` is stored UNINDEXED so it rides along on hits
    // without being tokenized, `content` is the searchable column. `porter unicode61` gives stemming +
    // Unicode-aware tokenization. If the system SQLite was built without FTS5, this DDL is where it fails.
    let ddl =
      "CREATE VIRTUAL TABLE IF NOT EXISTS \(table) USING fts5"
      + "(doc_id UNINDEXED, content, tokenize = 'porter unicode61');"
    var err: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, ddl, nil, nil, &err) == SQLITE_OK else {
      let message = err.map { String(cString: $0) } ?? "could not create FTS5 table"
      sqlite3_free(err)
      sqlite3_close(handle)
      throw SearchError.backend(
        "\(message) — the system SQLite may lack FTS5 support")
    }

    // Rebuild the id→rowid map from any rows a persisted database already holds.
    self.rowIDs = try Self.fetchRowIDs(db: handle, table: table)
  }

  public func index(_ document: TextDocument) async throws {
    let op = observer.begin("text.index")
    op.set("search.doc.id", document.id)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    do {
      if let existing = rowIDs[document.id] {
        try execute("DELETE FROM \(table) WHERE rowid = ?;") { stmt in
          sqlite3_bind_int64(stmt, 1, existing)
        }
      }
      try execute("INSERT INTO \(table) (doc_id, content) VALUES (?, ?);") { stmt in
        Self.bindText(stmt, 1, document.id)
        Self.bindText(stmt, 2, document.content)
      }
      rowIDs[document.id] = sqlite3_last_insert_rowid(db)
      metrics.counter("\(metricName)_requests").increment()
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "text index failed")
      throw error
    }
  }

  public func search(_ query: String, limit: Int) async throws -> [TextSearchResult] {
    let op = observer.begin("text.search")
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    guard let match = Self.matchExpression(for: query) else {
      metrics.counter("\(metricName)_requests").increment()
      op.set("search.results", 0)
      return []
    }

    do {
      var results: [TextSearchResult] = []
      let sql =
        "SELECT doc_id, content, bm25(\(table)) FROM \(table) "
        + "WHERE \(table) MATCH ? ORDER BY bm25(\(table)) ASC LIMIT ?;"
      try execute(sql) { stmt in
        Self.bindText(stmt, 1, match)
        sqlite3_bind_int(stmt, 2, limit > 0 ? Int32(limit) : -1)
      } eachRow: { stmt in
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let content = String(cString: sqlite3_column_text(stmt, 1))
        // SQLite's bm25() returns smaller (more negative) values for better matches; negate so the
        // public score reads higher-is-better while ORDER BY ASC still yields best-first.
        let score = -sqlite3_column_double(stmt, 2)
        results.append(TextSearchResult(id: id, content: content, score: score))
      }
      metrics.counter("\(metricName)_requests").increment()
      op.set("search.results", results.count)
      return results
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "text search failed")
      throw error
    }
  }

  public func delete(id: String) async throws {
    let op = observer.begin("text.delete")
    op.set("search.doc.id", id)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    guard let existing = rowIDs[id] else {
      // Missing id is a silent no-op, matching Go's providers.
      metrics.counter("\(metricName)_requests").increment()
      return
    }
    do {
      try execute("DELETE FROM \(table) WHERE rowid = ?;") { stmt in
        sqlite3_bind_int64(stmt, 1, existing)
      }
      rowIDs[id] = nil
      metrics.counter("\(metricName)_requests").increment()
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "text delete failed")
      throw error
    }
  }

  public func wipe() async throws {
    let op = observer.begin("text.wipe")
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    do {
      try execute("DELETE FROM \(table);")
      rowIDs.removeAll()
      metrics.counter("\(metricName)_requests").increment()
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "text wipe failed")
      throw error
    }
  }

  /// Test/inspection seam: the number of documents currently indexed.
  public var count: Int { rowIDs.count }

  // MARK: - SQLite plumbing

  /// Prepares `sql`, runs `bind` to set parameters, then either steps to completion (no `eachRow`) or
  /// invokes `eachRow` for every result row. Finalizes the statement on every path. Delegates to the
  /// static form so ``init`` (which can't touch actor-isolated state) can share the same plumbing.
  private func execute(
    _ sql: String,
    bind: (OpaquePointer?) -> Void = { _ in },
    eachRow: ((OpaquePointer?) -> Void)? = nil
  ) throws {
    try Self.execute(db: db, sql, bind: bind, eachRow: eachRow)
  }

  private static func execute(
    db: OpaquePointer,
    _ sql: String,
    bind: (OpaquePointer?) -> Void = { _ in },
    eachRow: ((OpaquePointer?) -> Void)? = nil
  ) throws {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      let message = String(cString: sqlite3_errmsg(db))
      sqlite3_finalize(stmt)
      throw SearchError.backend(message)
    }
    defer { sqlite3_finalize(stmt) }

    bind(stmt)

    if let eachRow {
      var status = sqlite3_step(stmt)
      while status == SQLITE_ROW {
        eachRow(stmt)
        status = sqlite3_step(stmt)
      }
      guard status == SQLITE_DONE else {
        throw SearchError.backend(String(cString: sqlite3_errmsg(db)))
      }
    } else {
      guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw SearchError.backend(String(cString: sqlite3_errmsg(db)))
      }
    }
  }

  /// Reads the current table's id→rowid pairs into a fresh map (used at construction against a persisted
  /// file). Static so ``init`` can call it before the actor is fully formed.
  private static func fetchRowIDs(db: OpaquePointer, table: String) throws -> [String: Int64] {
    var map: [String: Int64] = [:]
    try execute(
      db: db, "SELECT rowid, doc_id FROM \(table);",
      eachRow: { stmt in
        let rowid = sqlite3_column_int64(stmt, 0)
        let id = String(cString: sqlite3_column_text(stmt, 1))
        map[id] = rowid
      })
    return map
  }

  private func recordLatency(since start: ContinuousClock.Instant) {
    metrics.histogram("\(metricName)_latency_ms").record(start.duration(to: .now).millisecondsValue)
  }

  /// Binds `value` as a text parameter, copying it (`SQLITE_TRANSIENT`) so the Swift buffer need only live
  /// for the call.
  private static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
    _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, sqliteTransient) }
  }

  /// Builds an FTS5 MATCH expression from free-text `query`: split into alphanumeric terms, quote each as
  /// an FTS5 string literal, and OR them so a document matching more terms ranks higher. Returns `nil`
  /// when the query has no usable terms (so the caller short-circuits to an empty result set).
  static func matchExpression(for query: String) -> String? {
    let terms = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    guard !terms.isEmpty else { return nil }
    return
      terms
      .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
      .joined(separator: " OR ")
  }

  /// A valid unquoted SQL identifier: non-empty, ASCII letters/digits/underscore, not starting with a
  /// digit. Used to gate the interpolated table name.
  static func isValidIdentifier(_ name: String) -> Bool {
    guard let first = name.first, first == "_" || first.isLetter else { return false }
    return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
      && name.allSatisfy { $0.isASCII }
  }
}
