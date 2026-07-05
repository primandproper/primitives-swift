import Foundation

/// The set of content types the encoding layer negotiates, ported from the `ContentType*` package
/// variables in platform-go's `encoding/content_type.go`.
///
/// Go models each content type as a `*contentType` (a pointer to a MIME string) and compares by
/// pointer identity. Swift gets a closed, self-validating enum — the same move ``Cryptography``'s
/// `EncryptionProvider` and ``Filtering``'s `SortDirection` make. The raw value **is** the canonical
/// MIME string Go uses (`buildContentType(contentTypeJSON)` etc.), so:
///   * the `Content-Type` header serialization is just ``ContentType/rawValue`` (Go's
///     `ContentTypeToString`), and
///   * the wire shape of a Go-authored config (`{"contentType":"application/json"}`) decodes directly.
///
/// **Only `json` has a first-party Foundation codec.** The other four cases still exist so a
/// Go-authored content-type string keeps parsing (and a config keeps decoding), but selecting a codec
/// for them throws ``EncoderError/unsupportedContentType(_:)`` — see ``ContentType/makeClientEncoder()``.
/// This mirrors how ``Cryptography`` keeps the `salsa20` `EncryptionProvider` case decodable while its
/// factory throws `.unsupportedProvider`.
public enum ContentType: String, Codable, Sendable, CaseIterable {
  /// `application/json` — the only content type with a first-party Foundation codec
  /// (`JSONEncoder`/`JSONDecoder`). See ``JSONClientEncoder``.
  case json = "application/json"

  /// `application/xml`. Recognized for wire/config compatibility but **unsupported**: Foundation has no
  /// general XML `Codable` codec on Apple platforms (`PropertyListEncoder` covers plist, not arbitrary
  /// XML). Selecting it throws ``EncoderError/unsupportedContentType(_:)``.
  case xml = "application/xml"

  /// `application/toml`. Recognized but **unsupported** — no first-party TOML codec (Go used
  /// `BurntSushi/toml`). A faithful port means vendoring a TOML library; deferred until a flow needs it.
  case toml = "application/toml"

  /// `application/yaml`. Recognized but **unsupported** — no first-party YAML codec (Go used
  /// `gopkg.in/yaml.v3`). Deferred like ``toml``.
  case yaml = "application/yaml"

  /// `application/emoji`. Go's bespoke gob-then-`ecoji` scheme; **unsupported** and effectively
  /// unportable without reproducing both gob and ecoji. Kept only so the content-type string still
  /// parses.
  case emoji = "application/emoji"

  /// The canonical `Content-Type` header value, ported from Go's `ContentTypeToString`. Equal to
  /// ``rawValue``; exposed under an intent-revealing name for call sites setting request headers.
  public var headerValue: String { rawValue }

  /// Resolves a `Content-Type` header value to a ``ContentType``, ported from Go's
  /// `contentTypeFromString`.
  ///
  /// Reproduces Go's lenient negotiation behavior exactly:
  ///   * parameters are stripped, so `"application/json; charset=utf-8"` resolves to ``json`` (Go used
  ///     `mime.ParseMediaType`; splitting on the first `;` is the equivalent for a header value);
  ///   * the base media type is trimmed and lowercased before matching;
  ///   * an empty or unrecognized value falls back to ``json`` (Go's `defaultContentType`).
  ///
  /// This is deliberately lenient where the enum's own `Codable` conformance is strict: negotiation off
  /// an untrusted HTTP header should degrade to a sensible default, whereas a config value decoding to a
  /// bogus content type should surface as a decode failure.
  public static func from(header value: String) -> ContentType {
    let base = value.split(separator: ";", maxSplits: 1).first.map(String.init) ?? value
    let normalized = base.trimmingCharacters(in: .whitespaces).lowercased()
    return ContentType(rawValue: normalized) ?? .json
  }
}
