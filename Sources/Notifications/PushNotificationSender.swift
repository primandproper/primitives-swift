/// Sends push notifications to device tokens, ported from platform-go's
/// `mobile.PushNotificationSender` interface (`push_sender.go`).
///
/// Go's `SendPush(ctx context.Context, platform, token string, msg PushMessage) error` drops
/// `context.Context` for structured concurrency (per this port's settled conventions) and `error` for
/// `throws`. Implementations route internally by `platform` ("ios" or "android"), matching Go's contract.
///
/// The only implementations shipped here are ``NoopPushNotificationSender`` and
/// ``MockPushNotificationSender``: real APNs/FCM sending is a server concern and gets the salsa20
/// treatment — see ``Notifications`` and ``NotificationsConfig``.
public protocol PushNotificationSender: Sendable {
  /// Sends a push notification to a single device token.
  /// - Parameters:
  ///   - platform: `"ios"` or `"android"`; implementations filter by platform.
  ///   - token: the device token to push to.
  ///   - message: the notification content.
  func sendPush(platform: String, token: String, message: PushMessage) async throws
}
