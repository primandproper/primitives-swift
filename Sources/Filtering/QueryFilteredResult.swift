/// A list payload plus its pagination, ported from platform-go's `filtering.QueryFilteredResult[T]`.
///
/// In Go the `Pagination` is an embedded (flattened) struct, so on the wire its fields sit at the top
/// level alongside `data` — not nested. We reproduce that flattening with hand-written `Codable`.
///
/// > Note: For most client paths the API wraps responses in ``APIResponse`` instead, where pagination
/// > *is* nested under `"pagination"`. This type is provided for fidelity with endpoints that return
/// > the bare flattened envelope.
public struct QueryFilteredResult<T: Codable & Sendable>: Codable, Sendable {
  public var data: [T]
  public var pagination: Pagination

  public init(data: [T], pagination: Pagination) {
    self.data = data
    self.pagination = pagination
  }

  private enum CodingKeys: String, CodingKey {
    case data
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    data = try container.decode([T].self, forKey: .data)
    // Pagination's fields are flattened to the same level, so decode it from the same decoder.
    pagination = try Pagination(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(data, forKey: .data)
    try pagination.encode(to: encoder)
  }
}
