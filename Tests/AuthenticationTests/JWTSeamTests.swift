import CryptoKit
import Foundation
import Testing

@testable import Authentication

/// REPO-05: regression tests for the ``JWTParsing`` seam — the live ``JWTParser`` conformance plus the
/// Noop and Mock doubles.
@Suite("JWTParsing seam — Noop + Mock")
struct JWTParsingSeamTests {
  private let key = Data("HEREISA32CHARSECRETWHICHISMADEUP".utf8)
  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func sign(_ claims: [String: Any]) -> String {
    let header = try! JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"])
    let payload = try! JSONSerialization.data(withJSONObject: claims)
    let input = Base64URLNoPad.encode(header) + "." + Base64URLNoPad.encode(payload)
    let mac = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: SymmetricKey(data: key))
    return input + "." + Base64URLNoPad.encode(Data(mac))
  }

  @Test("JWTParser conforms to the seam and parses through it")
  func liveConformance() throws {
    let parser: any JWTParsing = JWTParser(key: .hs256(secret: key))
    let token = sign(["sub": "u", "exp": 2_000_000])
    #expect(try parser.parse(token, at: now).subject == "u")
  }

  @Test("NoopJWTParser rejects every token (fails safe)")
  func noopRejects() {
    let noop = NoopJWTParser()
    #expect(throws: JWTError.malformed) {
      _ = try noop.parse(sign(["sub": "u", "exp": 2_000_000]), at: now)
    }
    #expect(throws: JWTError.malformed) {
      _ = try noop.parse("anything", at: now)
    }
  }

  @Test("MockJWTParser default rejects; a handler supplies canned claims; calls are recorded")
  func mockBehavior() throws {
    let canned = JWTClaims(raw: ["sub": .string("mock-user")])
    let mock = MockJWTParser(parseHandler: { token, _ in
      if token == "good" { return canned }
      throw JWTError.invalidSignature
    })
    #expect(try mock.parse("good", at: now).subject == "mock-user")
    #expect(throws: JWTError.invalidSignature) {
      _ = try mock.parse("bad", at: now)
    }
    #expect(mock.parseCalls.map(\.token) == ["good", "bad"])

    // Default (no handler) fails safe.
    #expect(throws: JWTError.malformed) {
      _ = try MockJWTParser().parse("x", at: now)
    }
  }

  @Test("the parse(_:) convenience delegates to parse(_:at:)")
  func convenienceDelegates() throws {
    let mock = MockJWTParser(parseHandler: { _, _ in JWTClaims(raw: ["sub": .string("now-user")]) })
    #expect(try mock.parse("t").subject == "now-user")
    #expect(mock.parseCalls.count == 1)
  }
}
