/// Numeric range value types, ported from platform-go's `numbers/range.go`.
///
/// Go constrains these to its `Numeric` interface (every built-in int/uint/float). Swift's closest
/// idiomatic bound is `Comparable & Codable & Sendable`, which covers all of those and keeps the
/// types `Codable` for wire use. Go's `omitempty` on the optional `Max`/`Min` fields is reproduced
/// automatically: Swift's synthesized `Codable` encodes `Optional` properties with `encodeIfPresent`,
/// so a `nil` bound is omitted from JSON exactly as Go omits a `nil` pointer.

/// A range with a required minimum and optional maximum. Mirrors Go's `MinRange[T]`.
public struct MinRange<T: Comparable & Codable & Sendable>: Codable, Sendable, Equatable {
  public var min: T
  public var max: T?

  public init(min: T, max: T? = nil) {
    self.min = min
    self.max = max
  }

  /// Validates that `max`, when present, is not below `min`. Mirrors Go's `ValidateWithContext`,
  /// which deliberately does *not* reject a zero minimum: `min` is a value type that is always
  /// present, so a range starting at 0 is legitimate. Throws ``RangeValidationError/maxBelowMin``
  /// when the invariant is violated.
  public func validate() throws {
    if let max, max < min {
      throw RangeValidationError.maxBelowMin
    }
  }
}

/// A range where both bounds are optional. Mirrors Go's `OpenRange[T]`.
public struct OpenRange<T: Comparable & Codable & Sendable>: Codable, Sendable, Equatable {
  public var min: T?
  public var max: T?

  public init(min: T? = nil, max: T? = nil) {
    self.min = min
    self.max = max
  }
}

/// An update request for an open range. Mirrors Go's `OpenRangeUpdateRequestInput[T]`.
///
/// Structurally identical to ``OpenRange`` today; kept as a distinct type because it models a
/// different contract (a partial update payload), matching the Go source and leaving room for the
/// two to diverge without a breaking rename.
public struct OpenRangeUpdateRequestInput<T: Comparable & Codable & Sendable>: Codable, Sendable,
  Equatable
{
  public var min: T?
  public var max: T?

  public init(min: T? = nil, max: T? = nil) {
    self.min = min
    self.max = max
  }
}

/// Validation failures produced by ``MinRange/validate()``.
public enum RangeValidationError: Error, Equatable, Sendable {
  /// The maximum bound is below the minimum bound.
  case maxBelowMin
}
