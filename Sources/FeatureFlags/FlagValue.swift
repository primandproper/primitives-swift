import Foundation

/// A decoded JSON value, the Swift analogue of the arbitrary `any` platform-go's
/// `FeatureFlagManager.GetObjectValue` accepts as a default and returns as a result.
///
/// Go's method signature is `GetObjectValue(ctx, feature string, defaultValue any, evalCtx) (any, error)`.
/// `Any` is not `Sendable`, so it cannot cross the `async` boundary this port's methods use; this closed
/// enum is the value-typed, `Sendable` stand-in, the same move ``Authentication``'s `JSONValue` makes for
/// JWT claims. Unlike that type, ``FlagValue`` also needs to be **encoded**, not just decoded: a caller
/// supplies a default value (which the noop/mock implementations hand straight back), so this conforms to
/// both halves of `Codable`.
public enum FlagValue: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([FlagValue])
  case object([String: FlagValue])

  /// The string payload, or `nil` if this value is not a JSON string.
  public var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// The numeric payload as a `Double`, or `nil` if this value is not a JSON number.
  public var doubleValue: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  /// The boolean payload, or `nil` if this value is not a JSON boolean.
  public var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  /// The array payload, or `nil` if this value is not a JSON array.
  public var arrayValue: [FlagValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  /// The object payload, or `nil` if this value is not a JSON object.
  public var objectValue: [String: FlagValue]? {
    if case .object(let value) = self { return value }
    return nil
  }
}

extension FlagValue: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([FlagValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: FlagValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "unsupported JSON value")
    }
  }
}

extension FlagValue: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

extension FlagValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral,
  ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
  public init(stringLiteral value: String) { self = .string(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(nilLiteral: ()) { self = .null }
  public init(arrayLiteral elements: FlagValue...) { self = .array(elements) }
  public init(dictionaryLiteral elements: (String, FlagValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
