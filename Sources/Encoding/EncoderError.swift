import Foundation

/// Errors thrown by the encoding layer.
///
/// Named `EncoderError` rather than `EncodingError` on purpose: Foundation already ships a public
/// `EncodingError`, and shadowing it would make the bare name ambiguous at call sites that also
/// `import Foundation` (every one of them). The Go origin surfaced codec-selection failures implicitly
/// (its `switch` fell through to JSON); the Swift port makes "this content type has no codec here" an
/// explicit, typed failure — the same pattern ``Cryptography``'s `EncryptionError.unsupportedProvider`
/// uses for a recognized-but-unavailable provider.
///
/// Actual encode/decode failures are **not** wrapped here — Foundation's `JSONEncoder`/`JSONDecoder`
/// throw their own `EncodingError`/`DecodingError`, which carry richer context (coding path, key,
/// underlying error) than anything this layer could add. They propagate to the caller unchanged, and
/// (unlike the Go original) the layer stays decoupled from the observability graph — a caller traces a
/// thrown error at its own layer.
public enum EncoderError: Error, Equatable, Sendable {
  /// The requested ``ContentType`` is recognized but has no first-party codec on this platform (every
  /// case except ``ContentType/json``). Thrown by ``ContentType/makeClientEncoder()``.
  case unsupportedContentType(ContentType)

  /// The codec is deliberately disabled and cannot decode: thrown by ``NoopClientEncoder/decode(_:from:)``,
  /// which has no value to hand back (a codec-selection failure, in the same family as
  /// ``unsupportedContentType(_:)`` — not a wrapped Foundation decode error).
  case codecDisabled
}

extension EncoderError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedContentType(let contentType):
      return "unsupported content type: \(contentType.rawValue)"
    case .codecDisabled:
      return "codec is disabled and cannot decode"
    }
  }
}
