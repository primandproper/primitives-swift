import Foundation

/// The selectable push-notification provider, ported from the `ProviderAPNsFCM`/`ProviderNoop` string
/// constants in platform-go's `notifications/mobile/config` package.
///
/// Go models the provider as a bare `string` matched with a `switch` in `ProvidePushSender` (not a
/// `validation.In` enum), and defaults anything unrecognized — including empty — to noop. Swift gets a
/// closed enum plus ``resolve(_:)``, the same lenient-resolution shape ``Encoding``'s `ContentType` uses
/// for `from(header:)`.
public enum PushProvider: String, Codable, Sendable, CaseIterable {
  /// The real APNs + FCM implementation. Recognized for config compatibility but **unsupported** on this
  /// platform — see ``NotificationsConfig/makePushSender()``.
  case apnsFCM = "apns_fcm"
  /// The no-op implementation.
  case noop = "noop"

  /// Resolves a raw provider string the way Go's `ProvidePushSender` does: lowercased, trimmed, and
  /// defaulting to ``noop`` for anything unrecognized (including empty).
  public static func resolve(_ raw: String) -> PushProvider {
    let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
    return PushProvider(rawValue: normalized) ?? .noop
  }
}
