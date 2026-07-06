import Foundation
import os

/// A test double for ``JWTParsing``, following the same handler-closure + recorded-calls shape as
/// ``Analytics``'s `EventReporterMock` and platform-go's moq output.
///
/// ``parse(_:at:)`` delegates to an optional handler; an unset handler fails safe by throwing
/// ``JWTError/malformed`` (a verifier double must not accept by default). State is guarded by an
/// `OSAllocatedUnfairLock` so the type stays a synchronous, `Sendable` ``JWTParsing``.
///
/// The handler uses untyped `throws` (not typed `throws(JWTError)`): typed-throws function values
/// require macOS 15 / iOS 18, above this package's macOS 13 / iOS 16 floor.
public final class MockJWTParser: JWTParsing {
  public struct ParseCall: Sendable, Equatable {
    public let token: String
    public let date: Date
  }

  private let state = OSAllocatedUnfairLock(initialState: [ParseCall]())
  private let parseHandler: (@Sendable (String, Date) throws -> JWTClaims)?

  /// - Parameter parseHandler: invoked by ``parse(_:at:)``; if `nil`, `parse` throws
  ///   ``JWTError/malformed``.
  public init(parseHandler: (@Sendable (String, Date) throws -> JWTClaims)? = nil) {
    self.parseHandler = parseHandler
  }

  /// Every `(token, date)` pair passed to ``parse(_:at:)``, in order.
  public var parseCalls: [ParseCall] { state.withLock { $0 } }

  public func parse(_ token: String, at date: Date) throws -> JWTClaims {
    state.withLock { $0.append(ParseCall(token: token, date: date)) }
    if let parseHandler {
      return try parseHandler(token, date)
    }
    throw JWTError.malformed
  }
}
