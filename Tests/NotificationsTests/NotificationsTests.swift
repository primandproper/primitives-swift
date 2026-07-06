import Foundation
import Testing

@testable import Notifications

@Suite("PushMessage")
struct PushMessageTests {
  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = PushMessage(title: "New Message", body: "You have a new message!", badgeCount: 3)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PushMessage.self, from: data)
    #expect(decoded == original)
  }

  @Test("badgeCount defaults to nil")
  func defaultBadge() {
    let message = PushMessage(title: "title", body: "body")
    #expect(message.badgeCount == nil)
  }
}

@Suite("NoopPushNotificationSender")
struct NoopPushNotificationSenderTests {
  @Test("sendPush succeeds unconditionally, matching Go's Example_pushNotificationSender")
  func sendPushSucceeds() async throws {
    let sender = NoopPushNotificationSender()
    try await sender.sendPush(
      platform: "ios", token: "device-token-abc",
      message: PushMessage(title: "New Message", body: "You have a new message!"))
  }

  @Test("succeeds regardless of platform")
  func anyPlatform() async throws {
    let sender = NoopPushNotificationSender()
    try await sender.sendPush(
      platform: "android", token: "token", message: PushMessage(title: "t", body: "b"))
    try await sender.sendPush(
      platform: "unknown", token: "token", message: PushMessage(title: "t", body: "b"))
  }
}

@Suite("MockPushNotificationSender")
struct MockPushNotificationSenderTests {
  @Test("records every call in order")
  func recordsCalls() async throws {
    let sender = MockPushNotificationSender()
    let first = PushMessage(title: "first", body: "body-1")
    let second = PushMessage(title: "second", body: "body-2", badgeCount: 2)

    try await sender.sendPush(platform: "ios", token: "token-1", message: first)
    try await sender.sendPush(platform: "android", token: "token-2", message: second)

    let calls = await sender.calls
    #expect(
      calls == [
        .init(platform: "ios", token: "token-1", message: first),
        .init(platform: "android", token: "token-2", message: second),
      ])
  }

  @Test("still records a call that then throws the configured error")
  func recordsBeforeThrowing() async {
    let sender = MockPushNotificationSender(
      throwing: NotificationsError.unsupportedProvider(.apnsFCM))
    let message = PushMessage(title: "t", body: "b")

    await #expect(throws: NotificationsError.unsupportedProvider(.apnsFCM)) {
      try await sender.sendPush(platform: "ios", token: "token", message: message)
    }

    let calls = await sender.calls
    #expect(calls == [.init(platform: "ios", token: "token", message: message)])
  }
}

@Suite("MobileNotificationRequest")
struct MobileNotificationRequestTests {
  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = MobileNotificationRequest(
      requestType: "reminder",
      title: "title",
      body: "body",
      recipientUserIDs: ["user-1", "user-2"],
      context: ["key": "value"],
      badgeCount: 4,
      testID: "test-1")

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MobileNotificationRequest.self, from: data)
    #expect(decoded == original)
  }

  @Test("decodes the Go JSON wire shape")
  func decodesGoShape() throws {
    let json = Data(
      #"""
      {
        "context": {"orderID": "abc123"},
        "badgeCount": 1,
        "requestType": "order_shipped",
        "title": "Your order shipped",
        "body": "It's on the way!",
        "testID": "t-1",
        "recipientUserIDs": ["user-1"]
      }
      """#.utf8)

    let decoded = try JSONDecoder().decode(MobileNotificationRequest.self, from: json)
    #expect(decoded.context == ["orderID": "abc123"])
    #expect(decoded.badgeCount == 1)
    #expect(decoded.requestType == "order_shipped")
    #expect(decoded.title == "Your order shipped")
    #expect(decoded.body == "It's on the way!")
    #expect(decoded.testID == "t-1")
    #expect(decoded.recipientUserIDs == ["user-1"])
  }

  @Test("missing fields decode to Go zero values")
  func partialDecode() throws {
    let decoded = try JSONDecoder().decode(MobileNotificationRequest.self, from: Data("{}".utf8))
    #expect(decoded.context == nil)
    #expect(decoded.badgeCount == nil)
    #expect(decoded.requestType == "")
    #expect(decoded.title == "")
    #expect(decoded.body == "")
    #expect(decoded.testID == nil)
    #expect(decoded.recipientUserIDs == [])
  }

  @Test("omits omitempty keys when unset")
  func encodingOmitsEmptyOptionalKeys() throws {
    let request = MobileNotificationRequest(requestType: "reminder", title: "title", body: "body")
    let data = try JSONEncoder().encode(request)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["context"] == nil)
    #expect(json["badgeCount"] == nil)
    #expect(json["testID"] == nil)
    #expect(json["requestType"] as? String == "reminder")
    #expect(json["recipientUserIDs"] as? [String] == [])
  }
}

@Suite("PushProvider")
struct PushProviderTests {
  @Test("raw values mirror the Go string constants")
  func rawValues() {
    #expect(PushProvider.apnsFCM.rawValue == "apns_fcm")
    #expect(PushProvider.noop.rawValue == "noop")
  }

  @Test("resolve trims and lowercases before matching")
  func resolveNormalizes() {
    #expect(PushProvider.resolve("  APNS_FCM  ") == .apnsFCM)
    #expect(PushProvider.resolve("Noop") == .noop)
  }

  @Test("resolve defaults to noop for unknown or empty values, matching Go's lenient switch")
  func resolveDefaults() {
    #expect(PushProvider.resolve("unknown") == .noop)
    #expect(PushProvider.resolve("") == .noop)
  }
}

@Suite("NotificationsConfig")
struct NotificationsConfigTests {
  @Test("decodes the Go JSON shape")
  func decodesGoShape() throws {
    let json = Data(
      #"""
      {
        "apns": {"authKeyPath": "/keys/AuthKey.p8", "keyID": "KEY123", "teamID": "TEAM123", "bundleID": "com.example.app", "production": true},
        "fcm": {"credentialsPath": "/creds/fcm.json"},
        "provider": "apns_fcm"
      }
      """#.utf8)

    let config = try JSONDecoder().decode(NotificationsConfig.self, from: json)
    #expect(
      config.apns
        == APNsConfig(
          authKeyPath: "/keys/AuthKey.p8", keyID: "KEY123", teamID: "TEAM123",
          bundleID: "com.example.app",
          production: true))
    #expect(config.fcm == FCMConfig(credentialsPath: "/creds/fcm.json"))
    #expect(config.resolvedProvider == .apnsFCM)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = NotificationsConfig(
      provider: "noop",
      apns: APNsConfig(authKeyPath: "a", keyID: "k", teamID: "t", bundleID: "b", production: false),
      fcm: FCMConfig(credentialsPath: "c"))

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(NotificationsConfig.self, from: data)
    #expect(decoded == original)
  }

  @Test("missing apns/fcm decode to nil, matching Go's nil pointer zero value")
  func partialDecode() throws {
    let config = try JSONDecoder().decode(
      NotificationsConfig.self, from: Data(#"{"provider":"noop"}"#.utf8))
    #expect(config.apns == nil)
    #expect(config.fcm == nil)
  }

  @Test("empty provider resolves to noop")
  func emptyProviderResolvesToNoop() {
    #expect(NotificationsConfig().resolvedProvider == .noop)
  }

  @Test("noop provider builds a working sender")
  func noopProviderBuildsSender() async throws {
    let config = NotificationsConfig(provider: "noop")
    let sender = try config.makePushSender()
    try await sender.sendPush(
      platform: "ios", token: "token", message: PushMessage(title: "t", body: "b"))
  }

  @Test("unknown provider builds a noop sender, matching Go's lenient default")
  func unknownProviderBuildsNoopSender() throws {
    let config = NotificationsConfig(provider: "unknown")
    let sender = try config.makePushSender()
    #expect(sender is NoopPushNotificationSender)
  }

  @Test("apns_fcm provider throws unsupportedProvider, even with both configs present")
  func apnsFCMProviderThrows() {
    let config = NotificationsConfig(
      provider: "apns_fcm",
      apns: APNsConfig(authKeyPath: "a", keyID: "k", teamID: "t", bundleID: "b"),
      fcm: FCMConfig(credentialsPath: "c"))

    #expect(throws: NotificationsError.unsupportedProvider(.apnsFCM)) {
      _ = try config.makePushSender()
    }
  }

  @Test("apns_fcm provider throws even with neither sub-config present")
  func apnsFCMProviderThrowsWithoutSubConfigs() {
    let config = NotificationsConfig(provider: "apns_fcm")
    #expect(throws: NotificationsError.unsupportedProvider(.apnsFCM)) {
      _ = try config.makePushSender()
    }
  }
}

@Suite("NotificationsError messages")
struct NotificationsErrorTests {
  @Test("message names the offending provider")
  func message() {
    #expect(
      NotificationsError.unsupportedProvider(.apnsFCM).errorDescription
        == "unsupported push provider: apns_fcm")
  }
}
