import Foundation

/// A JSON-shaped event property value, the Swift analogue of the arbitrary `any` Go's
/// `map[string]any` properties argument holds (`EventReporter.AddUser`/`EventOccurred`).
///
/// `Any` is not `Sendable`, so a strict-concurrency Swift port needs a closed, value-typed
/// representation of "any property" instead — the same move ``Authentication``'s `JSONValue` makes for
/// JWT claims. This is a separate type (rather than a shared one) because each module in this port owns
/// its own copy of this shape, per the established convention.
public enum AnalyticsPropertyValue: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([AnalyticsPropertyValue])
  case object([String: AnalyticsPropertyValue])
}

extension AnalyticsPropertyValue: Codable {
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
    } else if let array = try? container.decode([AnalyticsPropertyValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: AnalyticsPropertyValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "unsupported analytics property value")
    }
  }

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

/// Literal conveniences so call sites can write `["plan": "pro", "seats": 3]` directly as a
/// `[String: AnalyticsPropertyValue]`, matching how naturally Go's `map[string]any{...}` reads at the
/// call site.
extension AnalyticsPropertyValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral,
  ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
  public init(stringLiteral value: String) { self = .string(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(nilLiteral: ()) { self = .null }
  public init(arrayLiteral elements: AnalyticsPropertyValue...) { self = .array(elements) }

  public init(dictionaryLiteral elements: (String, AnalyticsPropertyValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
