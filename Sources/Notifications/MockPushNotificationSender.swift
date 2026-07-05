/// A recording ``PushNotificationSender`` test double. Not a port of anything in platform-go — the Go
/// interface had no generated mock — but a client app driving code against ``PushNotificationSender``
/// needs something better than ``NoopPushNotificationSender`` to assert *what* was sent, so this fills
/// that gap the same way ``Observability``'s `RecordingObserver` does for spans.
///
/// An `actor` rather than a class with a lock: recording calls only needs isolation, not synchronous
/// access, and `sendPush` is already `async`.
public actor MockPushNotificationSender: PushNotificationSender {
  /// A single recorded `sendPush` invocation.
  public struct Call: Sendable, Equatable {
    public let platform: String
    public let token: String
    public let message: PushMessage
  }

  public private(set) var calls: [Call] = []
  private let errorToThrow: (any Error & Sendable)?

  /// - Parameter error: if set, every ``sendPush(platform:token:message:)`` call is still recorded, then
  ///   throws this error (after recording) instead of succeeding.
  public init(throwing error: (any Error & Sendable)? = nil) {
    self.errorToThrow = error
  }

  public func sendPush(platform: String, token: String, message: PushMessage) async throws {
    calls.append(Call(platform: platform, token: token, message: message))
    if let errorToThrow {
      throw errorToThrow
    }
  }
}
