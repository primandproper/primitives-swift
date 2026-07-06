import Filtering
import Foundation

/// Translates a ``Filtering/QueryFilter`` into a SQL fragment plus its bound ``SQLValue`` parameters —
/// the client-side analogue of platform-go's `database/filtering`, which turns the same filter into a
/// `WHERE`/`ORDER BY`/`LIMIT` clause server-side.
///
/// Timestamp bounds compare against RFC3339 text columns (SQLite's idiomatic date storage), so the
/// produced parameters are ``SQLValue/text(_:)``. `includeArchived == false` (or unset) adds an
/// `archivedColumn IS NULL` guard; a `sortBy` maps to `ORDER BY createdColumn ASC|DESC`; and
/// `maxResponseSize` maps to `LIMIT`. Only fields set on the filter contribute, matching Go's
/// nil-field-skips behavior.
public enum SQLFilter {
  /// The rendered SQL fragment (leading space, no trailing `;`) and its positional parameters, ready to
  /// append to a `SELECT ... FROM table` statement.
  public struct Clause: Sendable, Equatable {
    public let sql: String
    public let parameters: [SQLValue]
  }

  /// Builds the clause. Column names are caller-supplied (and must be trusted identifiers — they are
  /// interpolated, not bound); all user values are bound as parameters.
  public static func clause(
    for filter: QueryFilter,
    createdColumn: String = "created_at",
    updatedColumn: String = "updated_at",
    archivedColumn: String = "archived_at"
  ) -> Clause {
    var conditions: [String] = []
    var parameters: [SQLValue] = []

    // ISO8601DateFormatter is not Sendable, so it is built per-call rather than held as shared state.
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    func addBound(_ date: Date?, _ column: String, _ op: String) {
      guard let date else { return }
      conditions.append("\(column) \(op) ?")
      parameters.append(.text(formatter.string(from: date)))
    }

    addBound(filter.createdAfter, createdColumn, ">")
    addBound(filter.createdBefore, createdColumn, "<")
    addBound(filter.updatedAfter, updatedColumn, ">")
    addBound(filter.updatedBefore, updatedColumn, "<")

    // Exclude archived rows unless explicitly opted in, mirroring Go's default.
    if filter.includeArchived != true {
      conditions.append("\(archivedColumn) IS NULL")
    }

    var sql = ""
    if !conditions.isEmpty {
      sql += " WHERE " + conditions.joined(separator: " AND ")
    }

    if let sortBy = filter.sortBy {
      sql += " ORDER BY \(createdColumn) \(sortBy == .descending ? "DESC" : "ASC")"
    }

    if let limit = filter.maxResponseSize {
      sql += " LIMIT ?"
      parameters.append(.integer(Int64(limit)))
    }

    return Clause(sql: sql, parameters: parameters)
  }
}
