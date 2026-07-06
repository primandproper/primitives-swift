/// Configuration for ``OnDeviceEmbedder``. Has **no Go counterpart** — the on-device backend is a new,
/// iOS-native addition (see ``Embeddings``) — so unlike the other config types in this module, there is
/// no origin struct to mirror field-for-field. It is still lenient-`Codable` for consistency with the
/// rest of the port (see ``OpenAIEmbedderConfig``) and so `{}` decodes to a usable default.
public struct OnDeviceEmbedderConfig: Codable, Sendable, Equatable {
  /// A BCP-47 language code (e.g. `"en"`, `"fr"`) selecting which on-device model to load, passed to
  /// `NLLanguage(rawValue:)`. Empty resolves to `.english` in ``OnDeviceEmbedder/init(config:)``.
  public var language: String

  public init(language: String = "") {
    self.language = language
  }

  private enum CodingKeys: String, CodingKey {
    case language
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if !language.isEmpty { try c.encode(language, forKey: .language) }
  }
}
