import Foundation

/// Configuration selecting the encoding layer's content type, ported from platform-go's
/// `encoding.Config` (`config.go`) plus its `ProvideContentType` provider (`providers.go`).
///
/// Go's struct carries an `env:"CONTENT_TYPE" json:"contentType"` string and a `Required` validation
/// rule; iOS apps don't read the environment (per the port's settled conventions), so only the JSON
/// contract survives. The field stays a raw `String` — not a ``ContentType`` — precisely because Go
/// stored the raw value and resolved it *leniently* at `ProvideContentType` time via
/// `contentTypeFromString`. Keeping the raw string here preserves that: ``resolvedContentType`` runs
/// the same lenient negotiation (unknown/empty → ``ContentType/json``), so Go's `Required` check is
/// unnecessary — an absent value simply resolves to the default, matching Go's runtime behavior.
public struct EncodingConfig: Codable, Sendable, Equatable {
  /// The configured content type as a raw MIME string, e.g. `"application/json"`. Resolved via
  /// ``resolvedContentType``.
  public var contentType: String

  public init(contentType: String) {
    self.contentType = contentType
  }

  private enum CodingKeys: String, CodingKey {
    case contentType
  }

  /// The ``ContentType`` this config resolves to, via ``ContentType/from(header:)`` — the Swift analogue
  /// of Go's `ProvideContentType` → `contentTypeFromString`. Total: an empty or unrecognized value
  /// resolves to ``ContentType/json``.
  public var resolvedContentType: ContentType {
    ContentType.from(header: contentType)
  }

  /// Builds the configured ``ClientEncoder``, composing ``resolvedContentType`` with
  /// ``ContentType/makeClientEncoder()`` — the equivalent of wiring Go's `ProvideContentType` into
  /// `ProvideClientEncoder`.
  ///
  /// - Throws: ``EncoderError/unsupportedContentType(_:)`` when the resolved content type has no
  ///   first-party codec (anything but ``ContentType/json``).
  public func makeClientEncoder() throws -> any ClientEncoder {
    try resolvedContentType.makeClientEncoder()
  }
}
