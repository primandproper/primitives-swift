import Foundation

/// A no-op ``ClientEncoder`` representing a deliberately disabled codec.
///
/// ``encode(_:)`` produces no bytes (an empty `Data`) and ``decode(_:from:)`` throws
/// ``EncoderError/codecDisabled`` — unlike a value transform (``NoopEncryptorDecryptor``), an encoder
/// has no meaningful identity, so the Noop follows the *fail-safe* convention the ``Authentication``
/// TOTP/JWT Noops use: it refuses rather than silently fabricating a value. Use it where a
/// ``ClientEncoder`` is structurally required but no serialization should occur (a feature-flag-off
/// path, a test that asserts a codec is never exercised).
///
/// - Warning: this performs **no serialization**. `encode` discards its input; `decode` always throws.
///   Never use it as a stand-in for a real codec on a live encode/decode path.
public struct NoopClientEncoder: ClientEncoder {
  public let contentType: ContentType

  /// - Parameter contentType: the content type this Noop reports; defaults to ``ContentType/json``.
  public init(contentType: ContentType = .json) {
    self.contentType = contentType
  }

  /// Returns an empty `Data` without inspecting `value`.
  public func encode<T: Encodable>(_ value: T) throws -> Data { Data() }

  /// Always throws ``EncoderError/codecDisabled`` — the Noop has no value to decode into.
  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    throw EncoderError.codecDisabled
  }
}
