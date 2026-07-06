import Foundation
import Testing

@testable import Cookies

private struct Payload: Codable, Equatable {
  let userID: String
  let admin: Bool
}

@Suite("NoopCookieManaging")
struct NoopCookieManagingTests {
  @Test("encode produces the empty string and signs nothing")
  func encodeIsInert() throws {
    let noop = NoopCookieManaging()
    #expect(try noop.encode(name: "session", Payload(userID: "u1", admin: false)) == "")
  }

  @Test("decode refuses — a no-op can't synthesize a typed value")
  func decodeThrows() {
    let noop = NoopCookieManaging()
    #expect(throws: CookieError.malformedValue) {
      let _: Payload = try noop.decode(name: "session", from: "anything")
    }
  }

  @Test("buildCookie refuses — a no-op carries no domain")
  func buildCookieThrows() {
    let noop = NoopCookieManaging()
    #expect(throws: CookieError.missingDomain) {
      _ = try noop.buildCookie(name: "session", Payload(userID: "u1", admin: false))
    }
  }

  @Test("usable behind the CookieManaging existential")
  func behindProtocol() throws {
    let manager: any CookieManaging = NoopCookieManaging()
    #expect(try manager.encode(name: "s", Payload(userID: "u", admin: true)) == "")
  }
}

@Suite("MockCookieManaging")
struct MockCookieManagingTests {
  @Test("records encode calls with the serialized payload")
  func recordsEncode() throws {
    let mock = MockCookieManaging()
    let value = Payload(userID: "u1", admin: true)

    let token = try mock.encode(name: "session", value)

    #expect(!token.isEmpty)
    #expect(mock.encodeCalls.count == 1)
    #expect(mock.encodeCalls[0].name == "session")
    #expect(mock.encodeCalls[0].payload == (try JSONEncoder().encode(value)))
  }

  @Test("encode/decode round-trip returns the original value and records both calls")
  func roundTrip() throws {
    let mock = MockCookieManaging()
    let value = Payload(userID: "u42", admin: false)

    let token = try mock.encode(name: "session", value)
    let decoded: Payload = try mock.decode(name: "session", from: token)

    #expect(decoded == value)
    #expect(mock.decodeCalls.count == 1)
    #expect(mock.decodeCalls[0].encoded == token)
  }

  @Test("decode under a different name fails the name-binding check")
  func nameMismatchThrows() throws {
    let mock = MockCookieManaging()
    let token = try mock.encode(name: "session", Payload(userID: "u1", admin: true))

    #expect(throws: CookieError.macInvalid) {
      let _: Payload = try mock.decode(name: "other", from: token)
    }
  }

  @Test("buildCookie records the call and returns a cookie on the configured domain")
  func buildCookieRecords() throws {
    let mock = MockCookieManaging(domain: "example.test")
    let cookie = try mock.buildCookie(name: "session", Payload(userID: "u1", admin: false))

    #expect(cookie.name == "session")
    #expect(cookie.domain == "example.test")
    #expect(mock.buildCookieCalls.count == 1)
    #expect(mock.buildCookieCalls[0].name == "session")
  }
}
