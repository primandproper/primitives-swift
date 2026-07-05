/// A no-op ``PushNotificationSender``, ported from Go's `notifications/mobile/noop` package.
///
/// Sends nothing and never fails, matching Go's `pushNotificationSender.SendPush` returning `nil`
/// unconditionally. Used when no push backend is configured, or as a stand-in in tests.
public struct NoopPushNotificationSender: PushNotificationSender {
  public init() {}

  public func sendPush(platform: String, token: String, message: PushMessage) async throws {}
}
