import Foundation
import os

/// A recording test double for ``ClientEncoder``.
///
/// Because ``ClientEncoder/encode(_:)`` and ``ClientEncoder/decode(_:from:)`` are generic over the
/// value type, this mock cannot carry a typed per-value handler the way ``Cryptography``'s
/// `MockEncryptorDecryptor` does. Instead it records call metadata (counts, the bytes produced by each
/// `encode`, the bytes handed to each `decode`) and delegates to a backing codec — ``JSONClientEncoder``
/// by default — so round-tripping actually works. Optional `onEncode` / `onDecode` gate closures run
/// before delegation and can `throw` to exercise a caller's error path without needing the value type.
///
/// Thread safety comes from an `OSAllocatedUnfairLock` rather than an actor, keeping the type a
/// synchronous ``ClientEncoder`` (the protocol's methods are non-`async`). The gate closures use
/// untyped `throws`: typed-throws function *values* need macOS 15 / iOS 18, and this package targets
/// macOS 13 / iOS 16.
public final class MockClientEncoder: ClientEncoder {
  private struct State {
    var encodeCount = 0
    var decodeCount = 0
    var encodedPayloads: [Data] = []
    var decodedInputs: [Data] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let backing: any ClientEncoder
  private let onEncode: (@Sendable () throws -> Void)?
  private let onDecode: (@Sendable () throws -> Void)?

  public let contentType: ContentType

  /// - Parameters:
  ///   - contentType: the content type this mock reports; defaults to ``ContentType/json``.
  ///   - backing: the codec `encode`/`decode` delegate to for real behavior; defaults to
  ///     ``JSONClientEncoder``.
  ///   - onEncode: run at the start of every ``encode(_:)``; throw from it to make `encode` fail.
  ///   - onDecode: run at the start of every ``decode(_:from:)``; throw from it to make `decode` fail.
  public init(
    contentType: ContentType = .json,
    backing: any ClientEncoder = JSONClientEncoder(),
    onEncode: (@Sendable () throws -> Void)? = nil,
    onDecode: (@Sendable () throws -> Void)? = nil
  ) {
    self.contentType = contentType
    self.backing = backing
    self.onEncode = onEncode
    self.onDecode = onDecode
  }

  /// The number of ``encode(_:)`` calls.
  public var encodeCount: Int { state.withLock { $0.encodeCount } }
  /// The number of ``decode(_:from:)`` calls.
  public var decodeCount: Int { state.withLock { $0.decodeCount } }
  /// The bytes produced by each successful ``encode(_:)`` call, in order.
  public var encodedPayloads: [Data] { state.withLock { $0.encodedPayloads } }
  /// The bytes handed to each ``decode(_:from:)`` call, in order.
  public var decodedInputs: [Data] { state.withLock { $0.decodedInputs } }

  public func encode<T: Encodable>(_ value: T) throws -> Data {
    state.withLock { $0.encodeCount += 1 }
    try onEncode?()
    let data = try backing.encode(value)
    state.withLock { $0.encodedPayloads.append(data) }
    return data
  }

  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    state.withLock {
      $0.decodeCount += 1
      $0.decodedInputs.append(data)
    }
    try onDecode?()
    return try backing.decode(type, from: data)
  }
}
