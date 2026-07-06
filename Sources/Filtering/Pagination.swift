/// Pagination metadata returned alongside a list response, ported from platform-go's
/// `filtering.Pagination`. The pagination model is **cursor-based**, not offset/page-based: `cursor`
/// is the opaque token for the next page (the ID of the last item served), `previousCursor` echoes the
/// cursor that produced this page, and `maxResponseSize` is the page size (capped at ``QueryFilter/maxLimit``).
public struct Pagination: Codable, Sendable, Equatable {
  /// The filter the backend actually applied.
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

  private enum CodingKeys: String, CodingKey {
    case appliedQueryFilter
    case cursor
    case previousCursor
    case filteredCount
    case totalCount
    case maxResponseSize
  }

  /// Lenient decode matching Go's `encoding/json`: a missing key (or an explicit `null`) decodes to the
  /// field's zero value rather than throwing, so a bare `{}` and a partial object both round-trip — the
  /// same convention Observability (OBS-04) and FeatureFlags (SVC-03) follow (REPO-06).
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    appliedQueryFilter = try c.decodeIfPresent(QueryFilter.self, forKey: .appliedQueryFilter)
    cursor = try c.decodeIfPresent(String.self, forKey: .cursor) ?? ""
    previousCursor = try c.decodeIfPresent(String.self, forKey: .previousCursor) ?? ""
    filteredCount = try c.decodeIfPresent(UInt64.self, forKey: .filteredCount) ?? 0
    totalCount = try c.decodeIfPresent(UInt64.self, forKey: .totalCount) ?? 0
    maxResponseSize = try c.decodeIfPresent(UInt8.self, forKey: .maxResponseSize) ?? 0
  }
}
