import Foundation

/// A no-op ``NotificationCenterManager``, the client-side sibling of ``NoopPushNotificationSender``. The
/// safe default when notifications are disabled, so call sites don't have to nil-check a manager that may
/// not exist.
///
/// Unlike the noop *sender* (which reports every send as a success), authorization here reports **not
/// granted**: a manager that never prompts the user hasn't been granted anything, and callers should
/// degrade accordingly rather than believe they may post notifications. The token stream finishes
/// immediately, ``receiveDeviceToken(_:)`` discards, and ``schedule(_:)`` does nothing.
public struct NoopNotificationCenterManager: NotificationCenterManager {
  public init() {}

  public func requestAuthorization(options: AuthorizationOptions) async throws -> Bool { false }

  public func deviceTokens() -> AsyncStream<DeviceToken> {
    AsyncStream { $0.finish() }
  }

  public func receiveDeviceToken(_ deviceToken: Data) {}

  public func schedule(_ request: LocalNotificationRequest) async throws {}
}
