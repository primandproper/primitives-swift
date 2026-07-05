/// A generic, immutable bitmask over any fixed-width unsigned integer type, ported from
/// platform-go's `bitmask` package.
///
/// Go constrains its `Unsigned` interface to `~uint8 | ~uint16 | ~uint32 | ~uint64`; the Swift
/// equivalent is `FixedWidthInteger & UnsignedInteger`. We additionally require `Codable & Sendable`
/// so the type can cross concurrency domains and encode on the wire (Go achieves the latter with
/// hand-written `MarshalJSON`/`UnmarshalJSON`).
///
/// Immutability is free here: `Bitmask` is a `struct` with a single `let`, so it is a value type and
/// every operation naturally returns a new value, exactly as the Go methods return a fresh
/// `Bitmask` rather than mutating the receiver.
public struct Bitmask<T: FixedWidthInteger & UnsignedInteger & Codable & Sendable>: Sendable,
  Equatable, Hashable
{
  /// The underlying integer value. Mirrors Go's `Value()`.
  public let value: T

  /// Creates a bitmask with the given flags set (OR-combined). Mirrors Go's `New`.
  public init(_ flags: T...) {
    self.init(flags: flags)
  }

  /// Array-based counterpart to ``init(_:)`` for when flags are already in a collection.
  public init(flags: [T]) {
    var combined: T = 0
    for flag in flags { combined |= flag }
    self.value = combined
  }

  /// Creates a bitmask from a raw integer value. Mirrors Go's `FromValue`.
  public init(value: T) {
    self.value = value
  }

  /// Returns a new bitmask with the given flags set. Mirrors Go's `Set`.
  public func set(_ flags: T...) -> Bitmask {
    var updated = value
    for flag in flags { updated |= flag }
    return Bitmask(value: updated)
  }

  /// Returns a new bitmask with the given flags cleared. Mirrors Go's `Clear` (`&^`).
  public func clear(_ flags: T...) -> Bitmask {
    var updated = value
    for flag in flags { updated &= ~flag }
    return Bitmask(value: updated)
  }

  /// Returns a new bitmask with the given flags toggled. Mirrors Go's `Toggle`.
  public func toggle(_ flags: T...) -> Bitmask {
    var updated = value
    for flag in flags { updated ^= flag }
    return Bitmask(value: updated)
  }

  /// Reports whether `flag` is set. A zero flag is never considered set, matching Go's `Has`.
  public func has(_ flag: T) -> Bool {
    flag != 0 && value & flag == flag
  }

  /// Reports whether all the given flags are set. Empty input (combined zero) is `false`, matching
  /// Go's `HasAll`.
  public func hasAll(_ flags: T...) -> Bool {
    var combined: T = 0
    for flag in flags { combined |= flag }
    return combined != 0 && value & combined == combined
  }

  /// Reports whether any of the given flags are set. Mirrors Go's `HasAny`.
  public func hasAny(_ flags: T...) -> Bool {
    var combined: T = 0
    for flag in flags { combined |= flag }
    return value & combined != 0
  }

  /// Reports whether no flags are set. Mirrors Go's `IsEmpty`.
  public var isEmpty: Bool { value == 0 }

  /// The number of set bits. Mirrors Go's `Count` (`bits.OnesCount64`).
  public var count: Int { value.nonzeroBitCount }

  /// Returns the flags set in either bitmask. Mirrors Go's `Union`.
  public func union(_ other: Bitmask) -> Bitmask {
    Bitmask(value: value | other.value)
  }

  /// Returns only the flags set in both bitmasks. Mirrors Go's `Intersect`.
  public func intersect(_ other: Bitmask) -> Bitmask {
    Bitmask(value: value & other.value)
  }

  /// Returns the flags set in `self` but not in `other`. Mirrors Go's `Difference` (`&^`).
  public func difference(_ other: Bitmask) -> Bitmask {
    Bitmask(value: value & ~other.value)
  }
}

extension Bitmask: CustomStringConvertible {
  /// A zero-padded binary representation whose width is the full bit width of `T`. Mirrors Go's
  /// `String()`, which pads to `bits.OnesCount64(^T(0))` — i.e. the type's bit width.
  public var description: String {
    let binary = String(value, radix: 2)
    let padding = Swift.max(0, T.bitWidth - binary.count)
    return String(repeating: "0", count: padding) + binary
  }
}

extension Bitmask: Codable {
  /// Decodes a bare JSON number into the bitmask. Values that do not fit `T` (too large, or
  /// negative) throw automatically during integer decoding, matching Go's `ParseUint` width check.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.value = try container.decode(T.self)
  }

  /// Encodes the bitmask as a bare JSON number. Mirrors Go's `MarshalJSON`. Because this is a value
  /// type with value-semantics `Codable`, it encodes correctly even as an unaddressable struct
  /// field — the exact case Go's pointer-receiver marshaler once got wrong.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}
