import Encoding
import Foundation

/// Decodes `data` into a `T` using ``Encoding``'s codec for `contentType`, ported from platform-go's
/// generic `files.Decode[T]`. Builds a one-off encoder internally, same as Go.
///
/// - Throws: ``FilesError/emptyInput`` for empty `data` — mirrors Go's `decodeBytes` rejecting empty
///   input before any codec sees it, since no supported encoding treats an empty document as valid —
///   `EncoderError.unsupportedContentType(_:)` for a content type with no first-party codec (see
///   `ContentType.makeClientEncoder()`), or the codec's own decode error.
public func decode<T: Decodable>(_ type: T.Type, from data: Data, contentType: ContentType) throws
  -> T
{
  guard !data.isEmpty else { throw FilesError.emptyInput }
  let encoder = try contentType.makeClientEncoder()
  return try encoder.decode(type, from: data)
}

/// Reads all of `path` and decodes it into a `T`, ported from platform-go's `files.DecodeFile[T]`.
///
/// - Throws: the file-read error, or anything ``decode(_:from:contentType:)`` throws.
public func decodeFile<T: Decodable>(
  _ type: T.Type, atPath path: String, contentType: ContentType
) throws -> T {
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  return try decode(type, from: data, contentType: contentType)
}
