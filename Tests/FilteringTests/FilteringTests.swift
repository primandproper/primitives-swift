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
