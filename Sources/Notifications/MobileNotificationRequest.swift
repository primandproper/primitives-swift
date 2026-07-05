import Foundation

/// The generic message payload for mobile push notifications, ported from platform-go's
/// `mobile.MobileNotificationRequest` (`requests.go`). `requestType` determines which handler processes
/// the request; schedulers format the message.
///
/// Go's JSON tags are preserved exactly (`context`, `badgeCount`, `requestType`, `title`, `body`,
/// `testID`, `recipientUserIDs`) so a payload built by a Go scheduler decodes here unchanged, and one
/// built here encodes into a shape a Go consumer understands.
///
/// **Decode leniency, matching Go's zero values.** `requestType`/`title`/`body` have no `omitempty` tag
/// but are still plain `string`s in Go — a missing key unmarshals to `""`, not a decode failure.
/// `recipientUserIDs` similarly has no `omitempty`; a missing key (or Go's `null` for a nil slice)
/// decodes to an empty array here rather than failing. `context`/`badgeCount`/`testID` carry `omitempty`
/// and stay `Optional` on both sides: an absent key skips encoding, matching Go, and decodes to `nil`.
public struct MobileNotificationRequest: Codable, Sendable, Equatable {
  public var context: [String: String]?
  public var badgeCount: Int?
  public var requestType: String
  public var title: String
  public var body: String
  public var testID: String?
  public var recipientUserIDs: [String]

  public init(
    requestType: String,
    title: String,
    body: String,
    recipientUserIDs: [String] = [],
    context: [String: String]? = nil,
    badgeCount: Int? = nil,
    testID: String? = nil
  ) {
    self.requestType = requestType
    self.title = title
    self.body = body
    self.recipientUserIDs = recipientUserIDs
    self.context = context
    self.badgeCount = badgeCount
    self.testID = testID
  }

  private enum CodingKeys: String, CodingKey {
    case context
    case badgeCount
    case requestType
    case title
    case body
    case testID
    case recipientUserIDs
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    context = try c.decodeIfPresent([String: String].self, forKey: .context)
    badgeCount = try c.decodeIfPresent(Int.self, forKey: .badgeCount)
    requestType = try c.decodeIfPresent(String.self, forKey: .requestType) ?? ""
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
    testID = try c.decodeIfPresent(String.self, forKey: .testID)
    recipientUserIDs = try c.decodeIfPresent([String].self, forKey: .recipientUserIDs) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(context, forKey: .context)
    try c.encodeIfPresent(badgeCount, forKey: .badgeCount)
    try c.encode(requestType, forKey: .requestType)
    try c.encode(title, forKey: .title)
    try c.encode(body, forKey: .body)
    try c.encodeIfPresent(testID, forKey: .testID)
    try c.encode(recipientUserIDs, forKey: .recipientUserIDs)
  }
}
