import Foundation

#if canImport(UserNotifications)
import UserNotifications

/// The live ``NotificationCenterManager``, backed by Apple's built-in **UserNotifications** framework.
/// This is the iOS-native client seam the module previously lacked: where ``PushNotificationSender``
/// describes a *server* pushing to a device, this wraps the on-device `UNUserNotificationCenter` an app
/// actually drives. No external dependency — UserNotifications ships with the OS, the same "use the native
/// framework" choice this port makes for StoreKit (`Capitalism`) and CryptoKit (``Cryptography``).
///
/// A `final class` rather than an `actor`: the only shared mutable state is the device-token continuation
/// registry, which lives in a lock-backed ``DeviceTokenBroadcaster`` so the synchronous
/// ``deviceTokens()`` / ``receiveDeviceToken(_:)`` requirements need no actor hop. The two
/// center-touching methods resolve `UNUserNotificationCenter.current()` lazily, so constructing a manager
/// (e.g. to wire up token observation) never touches the notification center.
///
/// **Testing note.** ``requestAuthorization(options:)`` and ``schedule(_:)`` call
/// `UNUserNotificationCenter.current()`, which requires a real app bundle and can't be exercised
/// hermetically from the SwiftPM CLI — a faithful test needs an app host. Those live in the consuming
/// app's UI-test target. This package tests the parts that *are* hermetic: the device-token fan-out
/// (which never touches the center) and the pure ``PushMessage`` → `UNNotificationContent` /
/// ``LocalNotificationRequest/Trigger`` → `UNNotificationTrigger` mapping, exposed for that purpose as
/// the internal ``makeContent(from:)`` / ``makeTrigger(from:)`` / ``makeRequest(from:)`` helpers.
public final class SystemNotificationCenterManager: NotificationCenterManager {
  private let broadcaster = DeviceTokenBroadcaster()

  public init() {}

  public func requestAuthorization(options: AuthorizationOptions) async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(
      options: options.unAuthorizationOptions)
  }

  public func deviceTokens() -> AsyncStream<DeviceToken> {
    broadcaster.stream()
  }

  public func receiveDeviceToken(_ deviceToken: Data) {
    broadcaster.broadcast(DeviceToken(rawData: deviceToken))
  }

  public func schedule(_ request: LocalNotificationRequest) async throws {
    try await UNUserNotificationCenter.current().add(Self.makeRequest(from: request))
  }

  // MARK: - Pure mapping (hermetically testable; no `UNUserNotificationCenter` involved)

  /// Builds the notification content from a ``PushMessage``: title and body always, plus the app-icon
  /// badge when ``PushMessage/badgeCount`` is set.
  static func makeContent(from message: PushMessage) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = message.title
    content.body = message.body
    if let badgeCount = message.badgeCount {
      content.badge = NSNumber(value: badgeCount)
    }
    return content
  }

  /// Maps this seam's ``LocalNotificationRequest/Trigger`` onto a `UNNotificationTrigger`; `nil` stays
  /// `nil`, which `UNNotificationRequest` treats as "deliver immediately".
  static func makeTrigger(from trigger: LocalNotificationRequest.Trigger?) -> UNNotificationTrigger? {
    switch trigger {
    case nil:
      return nil
    case .timeInterval(let interval, let repeats):
      return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: repeats)
    }
  }

  /// Assembles the full `UNNotificationRequest` from a ``LocalNotificationRequest``.
  static func makeRequest(from request: LocalNotificationRequest) -> UNNotificationRequest {
    UNNotificationRequest(
      identifier: request.identifier,
      content: makeContent(from: request.message),
      trigger: makeTrigger(from: request.trigger))
  }
}

extension AuthorizationOptions {
  /// The native `UNAuthorizationOptions` this seam's option set maps onto.
  var unAuthorizationOptions: UNAuthorizationOptions {
    var options: UNAuthorizationOptions = []
    if contains(.alert) { options.insert(.alert) }
    if contains(.badge) { options.insert(.badge) }
    if contains(.sound) { options.insert(.sound) }
    if contains(.provisional) { options.insert(.provisional) }
    if contains(.carPlay) { options.insert(.carPlay) }
    if contains(.criticalAlert) { options.insert(.criticalAlert) }
    if contains(.providesAppNotificationSettings) { options.insert(.providesAppNotificationSettings) }
    return options
  }
}

#endif
