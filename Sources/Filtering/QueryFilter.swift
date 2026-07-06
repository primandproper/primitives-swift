import Foundation

/// The set of filters a client can apply to a list query, ported from platform-go's
/// `filtering.QueryFilter`. Every field is optional; on the client its primary job is producing the
/// query string for a list request (see ``queryItems()``).
///
/// JSON and URL representations both use straight, semantically-correct keys (`createdAfter` carries
/// the created-after bound, etc.). The hand-written `Codable` exists only to (de)serialize the time
/// fields as RFC3339 strings; the key names match the property names.
///
/// Two Go server-side helpers are deliberately dropped: `ExtractQueryFilterFromRequest`/`FromParams`
/// (parse an inbound `*url.Values`/request into a filter) and the filter-to-`Pagination` seeding
/// (`ToPagination`). A client only *emits* queries (see ``queryItems()``) and *reads* server-issued
/// ``Pagination``; it never parses inbound requests nor mints pagination, so neither has an iOS analogue.
public struct QueryFilter: Codable, Sendable, Equatable {
  /// Maximum page size the backend honors; larger requests are clamped server-side. (Go `MaxQueryFilterLimit`.)
  public static let maxLimit: UInt8 = 250
  /// Page size the backend falls back to when none is supplied. (Go `DefaultQueryFilterLimit`.)
  public static let defaultLimit: UInt8 = 50

  public var sortBy: SortDirection?
  public var createdAfter: Date?
  public var createdBefore: Date?
  public var updatedAfter: Date?
  public var updatedBefore: Date?
  public var maxResponseSize: UInt8?
  public var includeArchived: Bool?
  public var cursor: String?

  public init(
    sortBy: SortDirection? = nil,
    createdAfter: Date? = nil,
    createdBefore: Date? = nil,
    updatedAfter: Date? = nil,
    updatedBefore: Date? = nil,
    maxResponseSize: UInt8? = nil,
    includeArchived: Bool? = nil,
    cursor: String? = nil
  ) {
    self.sortBy = sortBy
    self.createdAfter = createdAfter
    self.createdBefore = createdBefore
    self.updatedAfter = updatedAfter
    self.updatedBefore = updatedBefore
    self.maxResponseSize = maxResponseSize
    self.includeArchived = includeArchived
    self.cursor = cursor
  }

  /// The backend's default filter: ascending sort, default page size. Mirrors Go `DefaultQueryFilter()`,
  /// whose `ToValues()` serializes to `limit=50&sortBy=asc` — use `QueryFilter.default.queryItems()`
  /// for the equivalent of Go's nil-filter request.
  public static var `default`: QueryFilter {
    QueryFilter(sortBy: .ascending, maxResponseSize: defaultLimit)
  }

  /// The URL query items for a list request, the client-side analogue of Go's `ToValues()`. Only
  /// non-nil fields are emitted; keys and formats mirror the Go `QueryKey*` constants exactly. A
  /// `maxResponseSize` above ``maxLimit`` is clamped down to it here, matching Go's `ToValues`, which
  /// caps `limit` at `MaxQueryFilterLimit` so a client never asks for a page the backend won't serve.
  /// Dates use RFC3339 with fractional seconds.
  public func queryItems() -> [URLQueryItem] {
    var items: [URLQueryItem] = []
    if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
    if let maxResponseSize {
      items.append(URLQueryItem(name: "limit", value: String(min(maxResponseSize, Self.maxLimit))))
    }
    if let sortBy { items.append(URLQueryItem(name: "sortBy", value: sortBy.rawValue)) }
    if let createdBefore {
      items.append(URLQueryItem(name: "createdBefore", value: RFC3339.string(from: createdBefore)))
    }
    if let createdAfter {
      items.append(URLQueryItem(name: "createdAfter", value: RFC3339.string(from: createdAfter)))
    }
    if let updatedBefore {
      items.append(URLQueryItem(name: "updatedBefore", value: RFC3339.string(from: updatedBefore)))
    }
    if let updatedAfter {
      items.append(URLQueryItem(name: "updatedAfter", value: RFC3339.string(from: updatedAfter)))
    }
    if let includeArchived {
      items.append(URLQueryItem(name: "includeArchived", value: includeArchived ? "true" : "false"))
    }
    return items
  }

  private enum CodingKeys: String, CodingKey {
    case sortBy
    case createdAfter
    case createdBefore
    case updatedAfter
    case updatedBefore
    case maxResponseSize
    case includeArchived
    case cursor
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sortBy = try c.decodeIfPresent(SortDirection.self, forKey: .sortBy)
    createdAfter = try Self.decodeDate(c, .createdAfter)
    createdBefore = try Self.decodeDate(c, .createdBefore)
    updatedAfter = try Self.decodeDate(c, .updatedAfter)
    updatedBefore = try Self.decodeDate(c, .updatedBefore)
    maxResponseSize = try c.decodeIfPresent(UInt8.self, forKey: .maxResponseSize)
    includeArchived = try c.decodeIfPresent(Bool.self, forKey: .includeArchived)
    cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(sortBy, forKey: .sortBy)
    try Self.encodeDate(&c, createdAfter, .createdAfter)
    try Self.encodeDate(&c, createdBefore, .createdBefore)
    try Self.encodeDate(&c, updatedAfter, .updatedAfter)
    try Self.encodeDate(&c, updatedBefore, .updatedBefore)
    try c.encodeIfPresent(maxResponseSize, forKey: .maxResponseSize)
    try c.encodeIfPresent(includeArchived, forKey: .includeArchived)
    try c.encodeIfPresent(cursor, forKey: .cursor)
  }

  private static func decodeDate(
    _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
  ) throws -> Date? {
    guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
    guard let date = RFC3339.date(from: raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: container,
        debugDescription: "expected an RFC3339 timestamp, got \"\(raw)\"")
    }
    return date
  }

  private static func encodeDate(
    _ container: inout KeyedEncodingContainer<CodingKeys>, _ date: Date?, _ key: CodingKeys
  ) throws {
    guard let date else { return }
    try container.encode(RFC3339.string(from: date), forKey: key)
  }
}
