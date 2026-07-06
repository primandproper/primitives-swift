import Foundation

/// The **client-side** notification seam this module was missing, wrapping `UNUserNotificationCenter`.
///
/// The module's other seam, ``PushNotificationSender``, is *server-shaped* — it describes a backend
/// pushing to a device token via APNs/FCM, which an iOS app can never implement (see ``Notifications``).
/// `NotificationCenterManager` is its client-side counterpart: the three things an app actually does with
/// the on-device notification center.
///
/// 1. ``requestAuthorization(options:)`` — prompt the user and learn whether notifications are granted.
/// 2. ``deviceTokens()`` / ``receiveDeviceToken(_:)`` — observe the APNs device token the OS hands the
///    app delegate in `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`. The app delegate
///    forwards the raw `Data` into ``receiveDeviceToken(_:)``; app code consumes the resulting
///    ``DeviceToken`` values (carrying both the raw bytes and their APNs hex string) off ``deviceTokens()``.
/// 3. ``schedule(_:)`` — post a *local* notification, built from a ``LocalNotificationRequest`` whose
///    payload reuses this module's existing ``PushMessage`` type.
///
/// The seam is deliberately native-framework-agnostic: no `UserNotifications` type crosses this boundary
/// (options are the module's own ``AuthorizationOptions``, not `UNAuthorizationOptions`), so the protocol,
/// its ``NoopNotificationCenterManager`` / ``MockNotificationCenterManager`` doubles, and any consuming
/// code compile on every platform. Only the live ``SystemNotificationCenterManager`` imports
/// `UserNotifications`, and it does so behind `#if canImport(UserNotifications)`.
///
/// Per this port's settled conventions (see `PORTING.md`), `context.Context` has no analogue and the
/// two center-touching methods are `async throws`.
public protocol NotificationCenterManager: Sendable {
  /// Requests notification authorization from the user, presenting the system prompt on first call.
  /// - Parameter options: the categories of interaction to request (alert/badge/sound/…).
  /// - Returns: `true` if the user granted (or had already granted) the requested authorization.
  func requestAuthorization(options: AuthorizationOptions) async throws -> Bool

  /// A stream of remote (APNs) device tokens. Each token registered via ``receiveDeviceToken(_:)`` after
  /// a consumer begins iterating is delivered to that consumer; multiple concurrent consumers each see
  /// every subsequent token. The stream ends when its consuming task is cancelled.
  func deviceTokens() -> AsyncStream<DeviceToken>

  /// Feeds a raw APNs device token into ``deviceTokens()``. Call this from the app delegate's
  /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` with the `Data` it receives.
  func receiveDeviceToken(_ deviceToken: Data)

  /// Schedules a local notification, building a `UNNotificationRequest` from `request`.
  func schedule(_ request: LocalNotificationRequest) async throws
}

extension NotificationCenterManager {
  /// Convenience overload requesting the ``AuthorizationOptions/standard`` set (alert, badge, sound).
  /// Swift protocol requirements can't carry default argument values, so this fills that role.
  public func requestAuthorization() async throws -> Bool {
    try await requestAuthorization(options: .standard)
  }
}

/// The categories of notification interaction an app can request, a native-agnostic mirror of
/// `UNAuthorizationOptions`. The live ``SystemNotificationCenterManager`` maps this onto the real
/// `UNAuthorizationOptions`; keeping our own type off the protocol boundary means the seam compiles
/// without `UserNotifications`.
public struct AuthorizationOptions: OptionSet, Sendable, Equatable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  /// Permission to display alerts.
  public static let alert = AuthorizationOptions(rawValue: 1 << 0)
  /// Permission to update the app icon badge.
  public static let badge = AuthorizationOptions(rawValue: 1 << 1)
  /// Permission to play sounds.
  public static let sound = AuthorizationOptions(rawValue: 1 << 2)
  /// Deliver quietly (provisionally) without an up-front prompt.
  public static let provisional = AuthorizationOptions(rawValue: 1 << 3)
  /// Permission to display notifications in a CarPlay environment.
  public static let carPlay = AuthorizationOptions(rawValue: 1 << 4)
  /// Permission to play critical alerts (bypassing Do Not Disturb / mute).
  public static let criticalAlert = AuthorizationOptions(rawValue: 1 << 5)
  /// Surface a button to the app's own in-app notification settings.
  public static let providesAppNotificationSettings = AuthorizationOptions(rawValue: 1 << 6)

  /// The common request set: alert, badge, and sound.
  public static let standard: AuthorizationOptions = [.alert, .badge, .sound]
}

/// A remote (APNs) device token. Carries both the raw bytes the OS hands the app delegate and their
/// canonical lowercase-hex ``hexString`` — the form a backend registers with APNs — so a consumer can use
/// whichever it needs without re-deriving one from the other.
public struct DeviceToken: Sendable, Equatable {
  /// The raw token bytes, exactly as received in
  /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
  public let rawData: Data
  /// The token as a lowercase hexadecimal string, the standard on-the-wire APNs representation.
  public let hexString: String

  public init(rawData: Data) {
    self.rawData = rawData
    self.hexString = rawData.map { String(format: "%02x", $0) }.joined()
  }
}

/// A request to post a *local* notification, reusing this module's ``PushMessage`` for its content.
///
/// The live conformer maps this onto a `UNNotificationRequest`: ``identifier`` is the request identifier,
/// ``message`` becomes the notification content (title/body, plus the app-icon badge when
/// ``PushMessage/badgeCount`` is set), and ``trigger`` becomes the delivery trigger — a `nil` trigger
/// delivers immediately, matching `UNNotificationRequest`'s `nil`-trigger semantics.
public struct LocalNotificationRequest: Sendable, Equatable {
  /// A unique identifier for the request; scheduling a second request with the same identifier replaces
  /// the first, matching `UNUserNotificationCenter`'s behavior.
  public var identifier: String
  /// The notification content, reusing the module's existing payload type.
  public var message: PushMessage
  /// When to deliver; `nil` delivers immediately.
  public var trigger: Trigger?

  /// When a scheduled notification fires, a native-agnostic mirror of the `UNNotificationTrigger` shapes
  /// this seam supports.
  public enum Trigger: Sendable, Equatable {
    /// Fire after a fixed number of seconds, optionally repeating (mapped to
    /// `UNTimeIntervalNotificationTrigger`).
    case timeInterval(TimeInterval, repeats: Bool)
  }

  public init(identifier: String, message: PushMessage, trigger: Trigger? = nil) {
    self.identifier = identifier
    self.message = message
    self.trigger = trigger
  }
}
