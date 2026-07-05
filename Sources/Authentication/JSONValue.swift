import Foundation

/// A decoded JSON value, the Swift analogue of the arbitrary `any` a Go `jwt.MapClaims` entry holds.
///
/// A JWT payload is arbitrary JSON, so ``JWTClaims`` needs a `Sendable`, value-typed representation of
/// "any claim" — Go's `map[string]any` does not translate to a strict-concurrency Swift world, where
/// `Any` is not `Sendable`. This closed enum fills that role and powers the typed accessors on
/// ``JWTClaims`` (mirroring Go's `Claims.Get` / `Claims.GetString`).
public enum JSONValue: Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([JSONValue])
  case object([String: JSONValue])

  /// The string payload, or `nil` if this value is not a JSON string. Mirrors the `(_, ok)` shape of
  /// Go's `GetString` — a non-string returns `nil`.
  public var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// The numeric payload as a `Double`, or `nil` if this value is not a JSON number. JWT `NumericDate`
  /// claims (`exp`/`nbf`/`iat`) decode through here.
  public var doubleValue: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }
}

extension JSONValue: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "unsupported JSON value")
    }
  }
}
