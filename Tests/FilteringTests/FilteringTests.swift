import Foundation
import Testing

@testable import Filtering

@Suite("SortDirection")
struct SortDirectionTests {
  @Test("raw values mirror the Go sentinels")
  func rawValues() {
    #expect(SortDirection.ascending.rawValue == "asc")
    #expect(SortDirection.descending.rawValue == "desc")
  }
}

@Suite("QueryFilter")
struct QueryFilterTests {
  @Test("default filter mirrors Go DefaultQueryFilter")
  func defaultFilter() {
    let f = QueryFilter.default
    #expect(f.sortBy == .ascending)
    #expect(f.maxResponseSize == QueryFilter.defaultLimit)
    #expect(QueryFilter.defaultLimit == 50)
    #expect(QueryFilter.maxLimit == 250)
  }

  @Test("queryItems emits only set fields with the correct keys")
  func queryItemsSubset() {
    let f = QueryFilter(
      sortBy: .descending, maxResponseSize: 25, includeArchived: true, cursor: "abc")
    let items = Dictionary(uniqueKeysWithValues: f.queryItems().map { ($0.name, $0.value) })

    #expect(items["cursor"] == "abc")
    #expect(items["limit"] == "25")
    #expect(items["sortBy"] == "desc")
    #expect(items["includeArchived"] == "true")
    #expect(items["createdBefore"] == nil)
    #expect(items["createdAfter"] == nil)
  }

  @Test("the default filter serializes to limit=50 and sortBy=asc, like Go's nil filter")
  func queryItemsDefault() {
    let items = Dictionary(
      uniqueKeysWithValues: QueryFilter.default.queryItems().map { ($0.name, $0.value) })
    #expect(items["limit"] == "50")
    #expect(items["sortBy"] == "asc")
    #expect(items.count == 2)
  }

  @Test("queryItems clamps an over-cap limit down to maxLimit, like Go's ToValues")
  func queryItemsClampsLimit() {
    let over = QueryFilter(maxResponseSize: 255)  // 255 > maxLimit (250)
    let items = Dictionary(uniqueKeysWithValues: over.queryItems().map { ($0.name, $0.value) })
    #expect(items["limit"] == "250")

    let under = QueryFilter(maxResponseSize: 25)
    let underItems = Dictionary(uniqueKeysWithValues: under.queryItems().map { ($0.name, $0.value) })
    #expect(underItems["limit"] == "25")
  }

  @Test("date query items use RFC3339 keys straight (not crossed)")
  func queryItemsDates() {
    let when = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14T22:13:20Z
    let f = QueryFilter(createdAfter: when, updatedBefore: when)
    let items = Dictionary(uniqueKeysWithValues: f.queryItems().map { ($0.name, $0.value) })

    // Straight URL mapping: the "createdAfter" key carries the created-after value.
    #expect(items["createdAfter"] == RFC3339.string(from: when))
    #expect(items["updatedBefore"] == RFC3339.string(from: when))
  }

  @Test("Codable round-trips through straight, semantically-correct JSON keys")
  func codableRoundTrip() throws {
    let after = Date(timeIntervalSince1970: 1_700_000_000)
    let original = QueryFilter(
      sortBy: .ascending, createdAfter: after, maxResponseSize: 10, cursor: "c")

    let data = try JSONEncoder().encode(original)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    // createdAfter lands under the "createdAfter" key.
    #expect(json["createdAfter"] != nil)
    #expect(json["createdBefore"] == nil)

    let decoded = try JSONDecoder().decode(QueryFilter.self, from: data)
    #expect(decoded.createdAfter == original.createdAfter)
    #expect(decoded.sortBy == .ascending)
    #expect(decoded.maxResponseSize == 10)
    #expect(decoded.cursor == "c")
  }

  @Test("decoding a non-RFC3339 timestamp throws")
  func codableBadDate() {
    let bad = Data(#"{"createdBefore":"not-a-date"}"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(QueryFilter.self, from: bad)
    }
  }
}

@Suite("Pagination & QueryFilteredResult")
struct PaginationTests {
  @Test("Pagination decodes from the Go wire shape")
  func paginationDecode() throws {
    let json = Data(
      #"{"appliedQueryFilter":null,"cursor":"c2","previousCursor":"c1","filteredCount":3,"totalCount":9,"maxResponseSize":50}"#
        .utf8)
    let p = try JSONDecoder().decode(Pagination.self, from: json)
    #expect(p.cursor == "c2")
    #expect(p.previousCursor == "c1")
    #expect(p.filteredCount == 3)
    #expect(p.totalCount == 9)
    #expect(p.maxResponseSize == 50)
    #expect(p.appliedQueryFilter == nil)
  }

  // REPO-06: Go's encoding/json decodes a bare `{}` (and missing/null fields) into a zero-value struct.
  // Swift's synthesized decode would throw on the absent non-optional keys; the lenient init closes that.
  @Test("Pagination decodes an empty object to Go zero values")
  func paginationEmptyObject() throws {
    let p = try JSONDecoder().decode(Pagination.self, from: Data("{}".utf8))
    #expect(p == Pagination())
    #expect(p.cursor == "")
    #expect(p.filteredCount == 0)
    #expect(p.maxResponseSize == 0)
    #expect(p.appliedQueryFilter == nil)
  }

  @Test("Pagination tolerates explicit null fields, decoding them to zero values")
  func paginationNullFields() throws {
    let json = Data(
      #"{"appliedQueryFilter":null,"cursor":null,"previousCursor":null,"filteredCount":null,"totalCount":null,"maxResponseSize":null}"#
        .utf8)
    let p = try JSONDecoder().decode(Pagination.self, from: json)
    #expect(p == Pagination())
  }

  @Test("QueryFilteredResult decodes an empty object: empty data and zero-value pagination")
  func filteredResultEmptyObject() throws {
    let result = try JSONDecoder().decode(QueryFilteredResult<String>.self, from: Data("{}".utf8))
    #expect(result.data.isEmpty)
    #expect(result.pagination == Pagination())
  }

  @Test("QueryFilteredResult treats a null data field as an empty slice")
  func filteredResultNullData() throws {
    let json = Data(#"{"data":null,"cursor":"c2"}"#.utf8)
    let result = try JSONDecoder().decode(QueryFilteredResult<String>.self, from: json)
    #expect(result.data.isEmpty)
    #expect(result.pagination.cursor == "c2")
  }

  @Test("QueryFilteredResult flattens pagination alongside data")
  func filteredResultFlattened() throws {
    let json = Data(
      #"{"data":["a","b"],"appliedQueryFilter":null,"cursor":"c2","previousCursor":"","filteredCount":2,"totalCount":2,"maxResponseSize":50}"#
        .utf8)
    let result = try JSONDecoder().decode(QueryFilteredResult<String>.self, from: json)
    #expect(result.data == ["a", "b"])
    #expect(result.pagination.cursor == "c2")
    #expect(result.pagination.totalCount == 2)

    // Re-encoding keeps the flattened shape.
    let reencoded =
      try JSONSerialization.jsonObject(with: try JSONEncoder().encode(result)) as? [String: Any]
    #expect(reencoded?["data"] != nil)
    #expect(reencoded?["cursor"] as? String == "c2")
    #expect(reencoded?["pagination"] == nil)
  }
}
