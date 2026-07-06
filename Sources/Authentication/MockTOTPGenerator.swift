import Foundation
import os

/// A test double for ``TOTPGenerator``, following the same handler-closure + recorded-calls shape as
/// ``Analytics``'s `EventReporterMock` and platform-go's moq output.
///
/// Each method delegates to an optional handler; an unset handler falls back to a quiet default (an
/// empty code / a thrown ``TOTPError/invalidCode`` / `false`), so a test stubs only what it exercises.
/// State is guarded by an `OSAllocatedUnfairLock` so the type stays a synchronous, `Sendable`
/// ``TOTPGenerator``.
///
/// Handlers use untyped `throws` (not typed `throws(TOTPError)`): typed-throws function values require
/// macOS 15 / iOS 18, above this package's macOS 13 / iOS 16 floor.
public final class MockTOTPGenerator: TOTPGenerator {
  public struct GenerateCall: Sendable, Equatable {
    public let secret: String
    public let date: Date
  }

  public struct VerifyCall: Sendable, Equatable {
    public let code: String
    public let secret: String
    public let date: Date
  }

  private struct State {
    var generateCalls: [GenerateCall] = []
    var verifyCalls: [VerifyCall] = []
    var isValidCalls: [VerifyCall] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let generateHandler: (@Sendable (String, Date) throws -> String)?
  private let verifyHandler: (@Sendable (String, String, Date) throws -> Void)?
  private let isValidHandler: (@Sendable (String, String, Date) throws -> Bool)?

  public init(
    generateHandler: (@Sendable (String, Date) throws -> String)? = nil,
    verifyHandler: (@Sendable (String, String, Date) throws -> Void)? = nil,
    isValidHandler: (@Sendable (String, String, Date) throws -> Bool)? = nil
  ) {
    self.generateHandler = generateHandler
    self.verifyHandler = verifyHandler
    self.isValidHandler = isValidHandler
  }

  public var generateCalls: [GenerateCall] { state.withLock { $0.generateCalls } }
  public var verifyCalls: [VerifyCall] { state.withLock { $0.verifyCalls } }
  public var isValidCalls: [VerifyCall] { state.withLock { $0.isValidCalls } }

  public func generate(secret: String, at date: Date) throws -> String {
    state.withLock { $0.generateCalls.append(GenerateCall(secret: secret, date: date)) }
    return try generateHandler?(secret, date) ?? ""
  }

  public func verify(code: String, secret: String, at date: Date) throws {
    state.withLock { $0.verifyCalls.append(VerifyCall(code: code, secret: secret, date: date)) }
    if let verifyHandler {
      try verifyHandler(code, secret, date)
    } else {
      throw TOTPError.invalidCode
    }
  }

  public func isValid(code: String, secret: String, at date: Date) throws -> Bool {
    state.withLock { $0.isValidCalls.append(VerifyCall(code: code, secret: secret, date: date)) }
    return try isValidHandler?(code, secret, date) ?? false
  }
}
