import Foundation

/// Errors thrown while building a ``PushNotificationSender`` from ``NotificationsConfig``.
public enum NotificationsError: Error, Equatable, Sendable {
  /// The configured ``PushProvider`` is recognized but not available on this platform (``PushProvider/apnsFCM``,
  /// whose Go backends — token-auth APNs and the Firebase Admin SDK — are server-only). See
  /// ``Notifications`` for the full rationale.
  case unsupportedProvider(PushProvider)
}

extension NotificationsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedProvider(let provider):
      return "unsupported push provider: \(provider.rawValue)"
    }
  }
}
