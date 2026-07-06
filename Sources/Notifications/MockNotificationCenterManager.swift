import Foundation
import os

/// A recording ``NotificationCenterManager`` test double, the client-side sibling of
/// ``MockPushNotificationSender`` and following the same conventions as `Capitalism`'s
/// `PurchaseManagerMock`: one optional handler closure per configurable method plus a recorded-calls list,
/// with an unset handler returning a quiet default rather than trapping.
///
/// An `actor` for the `async` methods (``requestAuthorization(options:)`` / ``schedule(_:)``), with the
/// synchronous device-token machinery held off the actor: ``deviceTokens()`` and ``receiveDeviceToken(_:)``
/// are synchronous protocol requirements, so they run against a lock-backed ``DeviceTokenBroadcaster`` and
/// a lock-backed received-token log rather than actor storage. That means a test can drive
/// ``receiveDeviceToken(_:)`` and observe it on ``deviceTokens()`` without ever `await`-ing the actor.
public actor MockNotificationCenterManager: NotificationCenterManager {
  public var requestAuthorizationHandler: (@Sendable (AuthorizationOptions) throws -> Bool)?
  public var scheduleHandler: (@Sendable (LocalNotificationRequest) throws -> Void)?

  public private(set) var requestAuthorizationCalls: [AuthorizationOptions] = []
  public private(set) var scheduledRequests: [LocalNotificationRequest] = []

  private nonisolated let broadcaster = DeviceTokenBroadcaster()
  private nonisolated let receivedTokensLock = OSAllocatedUnfairLock(initialState: [DeviceToken]())

  /// Every token passed to ``receiveDeviceToken(_:)``, in order. `nonisolated` (lock-backed) to match the
  /// synchronous method that records into it, so it reads without hopping onto the actor.
  public nonisolated var receivedDeviceTokens: [DeviceToken] {
    receivedTokensLock.withLock { $0 }
  }

  /// - Parameters:
  ///   - requestAuthorizationHandler: computes the granted result; unset returns `false` (not granted).
  ///   - scheduleHandler: invoked after recording a ``schedule(_:)`` call, e.g. to throw; unset is a no-op.
  public init(
    requestAuthorizationHandler: (@Sendable (AuthorizationOptions) throws -> Bool)? = nil,
    scheduleHandler: (@Sendable (LocalNotificationRequest) throws -> Void)? = nil
  ) {
    self.requestAuthorizationHandler = requestAuthorizationHandler
    self.scheduleHandler = scheduleHandler
  }

  public func requestAuthorization(options: AuthorizationOptions) throws -> Bool {
    requestAuthorizationCalls.append(options)
    return try requestAuthorizationHandler?(options) ?? false
  }

  public nonisolated func deviceTokens() -> AsyncStream<DeviceToken> {
    broadcaster.stream()
  }

  public nonisolated func receiveDeviceToken(_ deviceToken: Data) {
    let token = DeviceToken(rawData: deviceToken)
    receivedTokensLock.withLock { $0.append(token) }
    broadcaster.broadcast(token)
  }

  public func schedule(_ request: LocalNotificationRequest) throws {
    scheduledRequests.append(request)
    try scheduleHandler?(request)
  }
}
