import Foundation

/// APNs configuration for iOS push notifications, ported from platform-go's
/// `notifications/mobile/config.APNsConfig`.
///
/// Go tags each field with `env:` (read from the environment) and `json:`; per this port's settled
/// conventions, iOS apps don't configure from the environment, so only the JSON contract survives. This
/// still **decodes** even though nothing in this module can act on it — see ``NotificationsConfig``.
public struct APNsConfig: Codable, Sendable, Equatable {
  public var authKeyPath: String
  public var keyID: String
  public var teamID: String
  public var bundleID: String
  public var production: Bool

  public init(
    authKeyPath: String = "",
    keyID: String = "",
    teamID: String = "",
    bundleID: String = "",
    production: Bool = false
  ) {
    self.authKeyPath = authKeyPath
    self.keyID = keyID
    self.teamID = teamID
    self.bundleID = bundleID
    self.production = production
  }

  private enum CodingKeys: String, CodingKey {
    case authKeyPath
    case keyID
    case teamID
    case bundleID
    case production
  }
}

/// FCM configuration for Android push notifications, ported from platform-go's
/// `notifications/mobile/config.FCMConfig`. Decodes for wire compatibility; see ``NotificationsConfig``
/// for why nothing here ever constructs a real FCM sender.
public struct FCMConfig: Codable, Sendable, Equatable {
  /// The path to the Firebase service account JSON file. If empty, Go falls back to Application
  /// Default Credentials — a server-only concept with no bearing on this platform.
  public var credentialsPath: String

  public init(credentialsPath: String = "") {
    self.credentialsPath = credentialsPath
  }

  private enum CodingKeys: String, CodingKey {
    case credentialsPath
  }
}

/// The push notifications configuration, ported from platform-go's
/// `notifications/mobile/config.Config`.
///
/// Go's `ValidateWithContext` (ozzo-validation) requires at least one of `APNs`/`FCM` when
/// `Provider == "apns_fcm"`, guarding against a real backend silently failing to initialize. That
/// validation is unnecessary here: ``makePushSender()`` throws ``NotificationsError/unsupportedProvider(_:)``
/// for `apns_fcm` unconditionally, before ever inspecting ``apns``/``fcm`` — so there is no
/// partially-configured state to guard against on this platform.
public struct NotificationsConfig: Codable, Sendable, Equatable {
  public var apns: APNsConfig?
  public var fcm: FCMConfig?
  public var provider: String

  public init(provider: String = "", apns: APNsConfig? = nil, fcm: FCMConfig? = nil) {
    self.provider = provider
    self.apns = apns
    self.fcm = fcm
  }

  private enum CodingKeys: String, CodingKey {
    case apns
    case fcm
    case provider
  }

  /// The ``PushProvider`` this config resolves to, via ``PushProvider/resolve(_:)`` — the Swift
  /// analogue of Go's `ProvidePushSender`'s lowercase/trim/switch. Total: an empty or unrecognized value
  /// resolves to ``PushProvider/noop``.
  public var resolvedProvider: PushProvider {
    PushProvider.resolve(provider)
  }

  /// Builds the configured ``PushNotificationSender``, ported from Go's `Config.ProvidePushSender`.
  ///
  /// Go's factory initializes whichever of APNs/FCM is configured and wires both into a
  /// `MultiPlatformPushSender`, surfacing an initialization failure (bad key file, bad credentials) as
  /// an error rather than silently degrading to a noop. On this platform there is no real APNs/FCM
  /// client to initialize at all, so ``PushProvider/apnsFCM`` always throws
  /// ``NotificationsError/unsupportedProvider(_:)`` — the same "decode but refuse to hand back a sender
  /// it can't honor" seam ``Encoding``'s `ContentType.makeClientEncoder()` uses.
  ///
  /// - Throws: ``NotificationsError/unsupportedProvider(_:)`` when the resolved provider is
  ///   ``PushProvider/apnsFCM``.
  public func makePushSender() throws -> any PushNotificationSender {
    switch resolvedProvider {
    case .apnsFCM:
      throw NotificationsError.unsupportedProvider(.apnsFCM)
    case .noop:
      return NoopPushNotificationSender()
    }
  }
}
