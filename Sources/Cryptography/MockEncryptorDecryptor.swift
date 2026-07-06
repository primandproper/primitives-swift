import Foundation
import os

/// A test double for ``EncryptorDecryptor``, ported from platform-go's moq-generated
/// `encryptionmock.EncryptorDecryptorMock` (`cryptography/encryption/mock/encryptor_decryptor_mock.go`).
///
/// Go's moq output is a struct of `*Func` fields plus mutex-guarded call-recording slices, where an
/// unset `*Func` panics. This port keeps the shape — one handler closure per method plus a recorded-
/// calls list — but trades panic-on-unset for a quiet, useful default: an unset handler behaves like
/// ``NoopEncryptorDecryptor`` and returns `content` unchanged. Thread safety comes from an
/// `OSAllocatedUnfairLock` rather than an actor, so the type stays a synchronous ``EncryptorDecryptor``
/// (the protocol's methods are non-`async`).
///
/// The handlers use Swift's untyped `throws` (not typed `throws(EncryptionError)`): typed-throws
/// function *values* need macOS 15 / iOS 18, and this package targets macOS 13 / iOS 16.
public final class MockEncryptorDecryptor: EncryptorDecryptor {
  private struct State {
    var encryptCalls: [String] = []
    var decryptCalls: [String] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let encryptHandler: (@Sendable (String) throws -> String)?
  private let decryptHandler: (@Sendable (String) throws -> String)?

  /// - Parameters:
  ///   - encryptHandler: invoked by ``encrypt(_:)``; if `nil`, `encrypt` returns its input unchanged.
  ///   - decryptHandler: invoked by ``decrypt(_:)``; if `nil`, `decrypt` returns its input unchanged.
  public init(
    encryptHandler: (@Sendable (String) throws -> String)? = nil,
    decryptHandler: (@Sendable (String) throws -> String)? = nil
  ) {
    self.encryptHandler = encryptHandler
    self.decryptHandler = decryptHandler
  }

  /// The `content` values passed to every ``encrypt(_:)`` call, in order.
  public var encryptCalls: [String] { state.withLock { $0.encryptCalls } }
  /// The `content` values passed to every ``decrypt(_:)`` call, in order.
  public var decryptCalls: [String] { state.withLock { $0.decryptCalls } }

  public func encrypt(_ content: String) throws -> String {
    state.withLock { $0.encryptCalls.append(content) }
    return try encryptHandler?(content) ?? content
  }

  public func decrypt(_ content: String) throws -> String {
    state.withLock { $0.decryptCalls.append(content) }
    return try decryptHandler?(content) ?? content
  }
}
