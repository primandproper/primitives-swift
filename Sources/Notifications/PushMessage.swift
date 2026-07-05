import Foundation

/// The content of a push notification, ported from platform-go's `mobile.PushMessage`
/// (`push_sender.go`).
///
/// Go's struct carries no JSON tags — it is only ever constructed in-process and handed to a
/// ``PushNotificationSender`` — so there is no Go wire shape to preserve here; `Codable` conformance is
/// added purely for Swift-side convenience (e.g. round-tripping through a preview/debug screen).
public struct PushMessage: Codable, Sendable, Equatable {
  /// Optional app-icon badge count. `nil` leaves the badge untouched, matching Go's `*int`.
  public var badgeCount: Int?
  public var title: String
  public var body: String

  public init(title: String, body: String, badgeCount: Int? = nil) {
    self.title = title
    self.body = body
    self.badgeCount = badgeCount
  }
}
