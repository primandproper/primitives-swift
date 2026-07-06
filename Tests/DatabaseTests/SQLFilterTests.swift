import Filtering
import Foundation
import Testing

@testable import Database

@Suite("SQLFilter")
struct SQLFilterTests {
  @Test("an empty filter excludes archived rows by default")
  func emptyFilterExcludesArchived() {
    let clause = SQLFilter.clause(for: QueryFilter())
    #expect(clause.sql == " WHERE archived_at IS NULL")
    #expect(clause.parameters.isEmpty)
  }

  @Test("includeArchived drops the archived guard")
  func includeArchivedDropsGuard() {
    let clause = SQLFilter.clause(for: QueryFilter(includeArchived: true))
    #expect(clause.sql == "")
    #expect(clause.parameters.isEmpty)
  }

  @Test("time bounds and limit bind as parameters, sort renders inline")
  func boundsSortAndLimit() {
    let after = Date(timeIntervalSince1970: 1_000_000)
    let filter = QueryFilter(
      sortBy: .descending,
      createdAfter: after,
      maxResponseSize: 25,
      includeArchived: true)
    let clause = SQLFilter.clause(for: filter)
    #expect(clause.sql == " WHERE created_at > ? ORDER BY created_at DESC LIMIT ?")
    #expect(clause.parameters.count == 2)
    // First param is the RFC3339 created-after bound; last is the limit.
    #expect(clause.parameters.first?.stringValue != nil)
    #expect(clause.parameters.last == .integer(25))
  }

  @Test("custom column names are honored")
  func customColumns() {
    let clause = SQLFilter.clause(
      for: QueryFilter(updatedBefore: Date(timeIntervalSince1970: 0)),
      updatedColumn: "last_seen",
      archivedColumn: "deleted_at")
    #expect(clause.sql.contains("last_seen < ?"))
    #expect(clause.sql.contains("deleted_at IS NULL"))
  }
}
