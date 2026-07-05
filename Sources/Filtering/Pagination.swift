/// Pagination metadata returned alongside a list response, ported from platform-go's
/// `filtering.Pagination`. The pagination model is **cursor-based**, not offset/page-based: `cursor`
/// is the opaque token for the next page (the ID of the last item served), `previousCursor` echoes the
/// cursor that produced this page, and `maxResponseSize` is the page size (capped at ``QueryFilter/maxLimit``).
public struct Pagination: Codable, Sendable, Equatable {
  /// The filter the backend actually applied. Decoded via ``QueryFilter``'s crossed `CodingKeys`.
  public var appliedQueryFilter: QueryFilter?
  public var cursor: String
  public var previousCursor: String
  public var filteredCount: UInt64
  public var totalCount: UInt64
  public var maxResponseSize: UInt8

  public init(
    appliedQueryFilter: QueryFilter? = nil,
    cursor: String = "",
    previousCursor: String = "",
    filteredCount: UInt64 = 0,
    totalCount: UInt64 = 0,
    maxResponseSize: UInt8 = 0
  ) {
    self.appliedQueryFilter = appliedQueryFilter
    self.cursor = cursor
    self.previousCursor = previousCursor
    self.filteredCount = filteredCount
    self.totalCount = totalCount
    self.maxResponseSize = maxResponseSize
  }
}
