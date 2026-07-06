import Foundation
import Testing

@testable import Authentication

/// REPO-05: regression tests for the ``TOTPGenerator`` seam — the live ``TOTP`` conformance plus the
/// Noop and Mock doubles.
@Suite("TOTPGenerator seam — Noop + Mock")
struct TOTPGeneratorSeamTests {
  private let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  private let at = Date(timeIntervalSince1970: 59)

  @Test("TOTP conforms to the seam and produces its RFC vector through it")
  func liveConformance() throws {
    let generator: any TOTPGenerator = TOTP(algorithm: .sha1)
    #expect(try generator.generate(secret: secret, at: at) == "287082")
  }

  // MARK: Noop — fails safe (never a silent auth bypass)

  @Test("NoopTOTPGenerator returns a zero-filled placeholder and validates nothing")
  func noopFailsSafe() throws {
    let noop = NoopTOTPGenerator()
    #expect(noop.generate(secret: secret, at: at) == "000000")
    #expect(noop.isValid(code: "000000", secret: secret, at: at) == false)
    #expect(throws: TOTPError.invalidCode) {
      try noop.verify(code: "000000", secret: secret, at: at)
    }
    // Empty still surfaces the distinct codeRequired, matching TOTP's own contract.
    #expect(throws: TOTPError.codeRequired) {
      try noop.verify(code: "", secret: secret, at: at)
    }
  }

  @Test("NoopTOTPGenerator honors a custom digit count")
  func noopDigits() {
    #expect(NoopTOTPGenerator(digits: 8).generate(secret: secret, at: at) == "00000000")
  }

  // MARK: Mock — handler-driven, records calls

  @Test("MockTOTPGenerator routes through handlers and records calls")
  func mockHandlers() throws {
    let mock = MockTOTPGenerator(
      generateHandler: { _, _ in "123456" },
      isValidHandler: { code, _, _ in code == "123456" })
    #expect(try mock.generate(secret: secret, at: at) == "123456")
    #expect(try mock.isValid(code: "123456", secret: secret, at: at))
    #expect(try mock.isValid(code: "000000", secret: secret, at: at) == false)

    #expect(mock.generateCalls == [.init(secret: secret, date: at)])
    #expect(mock.isValidCalls.count == 2)
  }

  @Test("MockTOTPGenerator defaults fail safe (verify throws, isValid false, generate empty)")
  func mockDefaults() throws {
    let mock = MockTOTPGenerator()
    #expect(try mock.generate(secret: secret, at: at) == "")
    #expect(try mock.isValid(code: "x", secret: secret, at: at) == false)
    #expect(throws: TOTPError.invalidCode) {
      try mock.verify(code: "x", secret: secret, at: at)
    }
  }

  @Test("MockTOTPGenerator propagates a thrown error and the Now conveniences delegate")
  func mockThrowsAndConveniences() throws {
    let mock = MockTOTPGenerator(
      generateHandler: { _, _ in throw TOTPError.invalidSecret },
      verifyHandler: { _, _, _ in })
    #expect(throws: TOTPError.invalidSecret) {
      _ = try mock.generateNow(secret: secret)
    }
    // verifyNow / generateNow reach the same handlers via the protocol extension.
    #expect(throws: Never.self) {
      try mock.verifyNow(code: "any", secret: secret)
    }
  }
}
