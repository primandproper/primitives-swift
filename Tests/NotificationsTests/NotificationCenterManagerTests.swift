import Foundation
import Testing

@testable import Notifications

@Suite("DeviceToken")
struct DeviceTokenTests {
  @Test("hexString is the lowercase-hex APNs form of the raw bytes")
  func hexEncodesRawData() {
    let token = DeviceToken(rawData: Data([0x00, 0x0f, 0xab, 0xff]))
    #expect(token.hexString == "000fabff")
    #expect(token.rawData == Data([0x00, 0x0f, 0xab, 0xff]))
  }

  @Test("empty token is the empty hex string")
  func emptyToken() {
    #expect(DeviceToken(rawData: Data()).hexString == "")
  }
}

@Suite("AuthorizationOptions")
struct AuthorizationOptionsTests {
  @Test("standard is alert, badge, and sound")
  func standardSet() {
    #expect(AuthorizationOptions.standard == [.alert, .badge, .sound])
  }
}

@Suite("NoopNotificationCenterManager")
struct NoopNotificationCenterManagerTests {
  @Test("requestAuthorization reports not granted")
  func notGranted() async throws {
    let manager = NoopNotificationCenterManager()
    #expect(try await manager.requestAuthorization(options: .standard) == false)
    // Convenience overload takes the same path.
    #expect(try await manager.requestAuthorization() == false)
  }

  @Test("deviceTokens finishes immediately and receiveDeviceToken is discarded")
  func emptyTokenStream() async {
    let manager = NoopNotificationCenterManager()
    var iterator = manager.deviceTokens().makeAsyncIterator()
    manager.receiveDeviceToken(Data([0x01, 0x02]))
    #expect(await iterator.next() == nil)
  }

  @Test("schedule does nothing and never throws")
  func scheduleNoop() async throws {
    let manager = NoopNotificationCenterManager()
    try await manager.schedule(
      LocalNotificationRequest(identifier: "id", message: PushMessage(title: "t", body: "b")))
  }
}

@Suite("MockNotificationCenterManager")
struct MockNotificationCenterManagerTests {
  @Test("requestAuthorization records options and returns the handler result")
  func recordsAuthorization() async throws {
    let manager = MockNotificationCenterManager(
      requestAuthorizationHandler: { $0.contains(.alert) })

    let granted = try await manager.requestAuthorization(options: [.alert, .sound])
    #expect(granted == true)

    let denied = try await manager.requestAuthorization(options: [.badge])
    #expect(denied == false)

    let calls = await manager.requestAuthorizationCalls
    #expect(calls == [[.alert, .sound], [.badge]])
  }

  @Test("requestAuthorization defaults to not granted when no handler is set")
  func defaultsToNotGranted() async throws {
    let manager = MockNotificationCenterManager()
    #expect(try await manager.requestAuthorization(options: .standard) == false)
  }

  @Test("schedule records requests in order")
  func recordsScheduledRequests() async throws {
    let manager = MockNotificationCenterManager()
    let first = LocalNotificationRequest(identifier: "a", message: PushMessage(title: "t1", body: "b1"))
    let second = LocalNotificationRequest(
      identifier: "b", message: PushMessage(title: "t2", body: "b2", badgeCount: 2),
      trigger: .timeInterval(60, repeats: false))

    try await manager.schedule(first)
    try await manager.schedule(second)

    let scheduled = await manager.scheduledRequests
    #expect(scheduled == [first, second])
  }

  @Test("schedule still records a call that then throws the handler's error")
  func recordsBeforeThrowing() async {
    let manager = MockNotificationCenterManager(
      scheduleHandler: { _ in throw NotificationsError.unsupportedProvider(.apnsFCM) })
    let request = LocalNotificationRequest(identifier: "id", message: PushMessage(title: "t", body: "b"))

    await #expect(throws: NotificationsError.unsupportedProvider(.apnsFCM)) {
      try await manager.schedule(request)
    }
    let scheduled = await manager.scheduledRequests
    #expect(scheduled == [request])
  }

  @Test("receiveDeviceToken is recorded and delivered to a deviceTokens consumer")
  func deliversTokens() async {
    let manager = MockNotificationCenterManager()
    var iterator = manager.deviceTokens().makeAsyncIterator()

    manager.receiveDeviceToken(Data([0xab, 0xcd]))
    manager.receiveDeviceToken(Data([0x12, 0x34]))

    #expect(await iterator.next()?.hexString == "abcd")
    #expect(await iterator.next()?.hexString == "1234")
    #expect(manager.receivedDeviceTokens.map(\.hexString) == ["abcd", "1234"])
  }

  @Test("a token broadcasts to every active deviceTokens consumer")
  func broadcastsToMultipleConsumers() async {
    let manager = MockNotificationCenterManager()
    var first = manager.deviceTokens().makeAsyncIterator()
    var second = manager.deviceTokens().makeAsyncIterator()

    manager.receiveDeviceToken(Data([0xff]))

    #expect(await first.next()?.hexString == "ff")
    #expect(await second.next()?.hexString == "ff")
  }
}

#if canImport(UserNotifications)
import UserNotifications

/// Structural coverage of the live conformer's hermetic surface: the pure `PushMessage`/`Trigger` →
/// UserNotifications mapping and the device-token fan-out, neither of which touches
/// `UNUserNotificationCenter.current()`. Authorization/scheduling against the real center need an app host
/// and are not exercised here.
@Suite("SystemNotificationCenterManager mapping")
struct SystemNotificationCenterManagerTests {
  @Test("makeContent maps title, body, and badge")
  func contentWithBadge() {
    let content = SystemNotificationCenterManager.makeContent(
      from: PushMessage(title: "Hello", body: "World", badgeCount: 5))
    #expect(content.title == "Hello")
    #expect(content.body == "World")
    #expect(content.badge?.intValue == 5)
  }

  @Test("makeContent leaves the badge unset when badgeCount is nil")
  func contentWithoutBadge() {
    let content = SystemNotificationCenterManager.makeContent(
      from: PushMessage(title: "Hello", body: "World"))
    #expect(content.badge == nil)
  }

  @Test("makeTrigger maps nil to an immediate (nil) trigger")
  func immediateTrigger() {
    #expect(SystemNotificationCenterManager.makeTrigger(from: nil) == nil)
  }

  @Test("makeTrigger maps a timeInterval trigger")
  func timeIntervalTrigger() {
    let trigger =
      SystemNotificationCenterManager.makeTrigger(from: .timeInterval(60, repeats: true))
      as? UNTimeIntervalNotificationTrigger
    #expect(trigger?.timeInterval == 60)
    #expect(trigger?.repeats == true)
  }

  @Test("makeRequest carries identifier, content, and trigger")
  func fullRequest() {
    let request = SystemNotificationCenterManager.makeRequest(
      from: LocalNotificationRequest(
        identifier: "reminder-1", message: PushMessage(title: "t", body: "b")))
    #expect(request.identifier == "reminder-1")
    #expect(request.content.title == "t")
    #expect(request.trigger == nil)
  }

  @Test("AuthorizationOptions map onto the matching UNAuthorizationOptions")
  func authorizationOptionMapping() {
    let mapped: AuthorizationOptions = [.alert, .sound, .provisional]
    let un = mapped.unAuthorizationOptions
    #expect(un.contains(.alert))
    #expect(un.contains(.sound))
    #expect(un.contains(.provisional))
    #expect(!un.contains(.badge))
    #expect(AuthorizationOptions([]).unAuthorizationOptions.isEmpty)
  }

  @Test("device-token fan-out works without touching the notification center")
  func liveTokenFanOut() async {
    let manager = SystemNotificationCenterManager()
    var iterator = manager.deviceTokens().makeAsyncIterator()
    manager.receiveDeviceToken(Data([0x01, 0x02]))
    #expect(await iterator.next()?.hexString == "0102")
  }
}
#endif
