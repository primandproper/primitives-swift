import Foundation

/// A codec that encodes and decodes values for a single ``ContentType``, ported from platform-go's
/// `encoding.ClientEncoder` interface (`client_encoder.go`).
///
/// The Go interface is:
/// ```go
/// ContentType() string
/// Unmarshal(ctx, data []byte, v any) error
/// Encode(ctx, dest io.Writer, v any) error
/// EncodeReader(ctx, data any) (io.Reader, error)
/// ```
/// Three Go-isms collapse in the port:
///   * **`context.Context`** — threaded only for observability spans; dropped, like every other module
///     in this port (a codec is a pure transform).
///   * **`io.Writer` / `io.Reader`** — Go's `Encode(dest)` and `EncodeReader()` are two shapes of the
///     same operation. Swift returns `Data`, which streams trivially (`InputStream(data:)`) when a
///     caller genuinely needs a reader, so both fold into ``encode(_:)``.
///   * **`any` + `error` return** — replaced by `Encodable`/`Decodable` generics and `throws`, which is
///     the whole reason this module is thin: `Codable` already *is* the marshal/unmarshal machinery, so
///     the port carries only the content-type/codec-selection seam, not a re-implementation of it.
public protocol ClientEncoder: Sendable {
  /// The content type this encoder produces and consumes, mirroring Go's `ContentType()`.
  var contentType: ContentType { get }

  /// Encodes `value` to bytes, mirroring Go's `Encode`/`EncodeReader`.
  /// - Throws: the underlying codec's error (e.g. Foundation's `EncodingError`).
  func encode<T: Encodable>(_ value: T) throws -> Data

  /// Decodes `data` into a `T`, mirroring Go's `Unmarshal`.
  /// - Throws: the underlying codec's error (e.g. Foundation's `DecodingError`).
  func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

extension ContentType {
  /// Builds the ``ClientEncoder`` for this content type, ported from Go's `ProvideClientEncoder`
  /// (which selected behavior off the content type inside each method's `switch`).
  ///
  /// Only ``ContentType/json`` has a first-party Foundation codec; every other case throws
  /// ``EncoderError/unsupportedContentType(_:)``. This is the exact seam ``Cryptography`` uses — the
  /// enum case stays decodable so a Go-authored config/header doesn't break, but the factory refuses to
  /// hand back a codec it can't honor.
  ///
  /// - Throws: ``EncoderError/unsupportedContentType(_:)`` for any case but ``ContentType/json``.
  public func makeClientEncoder() throws -> any ClientEncoder {
    switch self {
    case .json:
      return JSONClientEncoder()
    case .xml, .toml, .yaml, .emoji:
      throw EncoderError.unsupportedContentType(self)
    }
  }
}
