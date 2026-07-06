import Foundation

/// A typed event with a JSON payload, ported from platform-go's `eventstream.Event`.
///
/// Go's ``payload`` field is `json.RawMessage` (`[]byte,omitempty`) — arbitrary, already-serialized
/// JSON carried opaquely alongside a `type` discriminator, so a caller decodes it into its own model
/// once it knows what `type` means. This mirrors that: ``payload`` is `Data`, and a Swift caller runs
/// its own `JSONDecoder.decode(_:from:)` over it. The Codable conformance below reconstructs that raw
/// pass-through (Foundation has no `json.RawMessage` analogue) so `payload` still appears in the wire
/// JSON as an embedded object/array/etc, not as a base64 string.
///
/// One edge case diverges from Go: `json.RawMessage.UnmarshalJSON` copies bytes verbatim, so decoding a
/// literal `"payload":null` gives Go's caller a non-nil `RawMessage("null")`. `decodeIfPresent` short-
/// circuits on a JSON `null` before this type's custom decoding ever runs, so the Swift side collapses
/// an explicit `null` payload to `nil`, same as an absent key. Nothing here observably depends on that
/// distinction, so it's left as a documented, minor deviation rather than special-cased.
public struct Event: Sendable, Equatable {
  public var type: String
  public var payload: Data?

  public init(type: String, payload: Data? = nil) {
    self.type = type
    self.payload = payload
  }
}

extension Event: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case payload
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    if let raw = try container.decodeIfPresent(RawJSON.self, forKey: .payload) {
      payload = try JSONEncoder().encode(raw)
    } else {
      payload = nil
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    if let payload {
      let raw = try JSONDecoder().decode(RawJSON.self, from: payload)
      try container.encode(raw, forKey: .payload)
    }
  }
}

/// A decoded JSON value used only as a bridge so ``Event/payload`` can round-trip arbitrary JSON as
/// embedded structure rather than a base64-encoded string, the way Go's `json.RawMessage` does.
///
/// This is intentionally private to the module: it's plumbing for ``Event``'s Codable conformance, not
/// a general-purpose JSON value type (``Authentication``'s `JSONValue` fills that role for claims and
/// is `Decodable`-only; this needs both directions to re-serialize a payload on encode).
enum RawJSON: Codable, Sendable, Equatable {
  case string(String)
  // `Decimal`, not `Double`: `Double` corrupts any JSON number Go's `json.RawMessage` would carry
  // verbatim — an int64 past 2^53 (a snowflake id) rounds, and a high-precision decimal truncates.
  // `JSONDecoder` builds a `Decimal` from the scanned digits (not via `Double`), and `JSONEncoder`
  // re-emits those digits, so a payload number round-trips to the same value it went in as.
  case number(Decimal)
  case bool(Bool)
  case null
  case array([RawJSON])
  case object([String: RawJSON])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Decimal.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([RawJSON].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: RawJSON].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}
