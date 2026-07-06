import Foundation

/// A single value bound into, or read back from, a SQLite statement — the port's typed replacement for
/// Go's `any`-typed `args ...any` / `Scan(dest ...any)` seam on `SQLQueryExecutor`.
///
/// SQLite's storage classes are NULL, INTEGER, REAL, TEXT, and BLOB; this enum is one case per class, so
/// binding and column reads round-trip without a lossy `any`. Convenience initializers cover the common
/// Swift scalar types (`Bool` maps to `0`/`1`, matching SQLite's own boolean convention).
public enum SQLValue: Sendable, Equatable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)
  case blob([UInt8])
}

extension SQLValue {
  public init(_ value: Int) { self = .integer(Int64(value)) }
  public init(_ value: Int64) { self = .integer(value) }
  public init(_ value: Double) { self = .real(value) }
  public init(_ value: String) { self = .text(value) }
  public init(_ value: Bool) { self = .integer(value ? 1 : 0) }
  public init(_ value: Data) { self = .blob([UInt8](value)) }

  /// `nil` binds SQL NULL; a present value binds as text. Convenience for optional string columns, the
  /// analogue of Go's `sql.NullString` helpers in `null_values.go`.
  public init(_ value: String?) { self = value.map { .text($0) } ?? .null }

  // MARK: Typed reads

  /// Reads a text value, or `nil` for NULL or a non-text column.
  public var stringValue: String? {
    if case .text(let value) = self { return value }
    return nil
  }

  /// Reads an integer value, or `nil` for NULL or a non-integer column.
  public var intValue: Int64? {
    if case .integer(let value) = self { return value }
    return nil
  }

  /// Reads a real value, or `nil` for NULL or a non-real column.
  public var doubleValue: Double? {
    if case .real(let value) = self { return value }
    return nil
  }

  /// Reads an integer as a boolean (`!= 0`), or `nil` for NULL or a non-integer column. Mirrors SQLite's
  /// boolean-as-integer convention.
  public var boolValue: Bool? {
    if case .integer(let value) = self { return value != 0 }
    return nil
  }

  /// Reads a blob value, or `nil` for NULL or a non-blob column.
  public var blobValue: [UInt8]? {
    if case .blob(let value) = self { return value }
    return nil
  }

  /// Whether this value is SQL NULL.
  public var isNull: Bool { self == .null }
}

extension SQLValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .text(value) }
}

extension SQLValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self = .integer(value) }
}

extension SQLValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) { self = .real(value) }
}

extension SQLValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .integer(value ? 1 : 0) }
}

extension SQLValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) { self = .null }
}
