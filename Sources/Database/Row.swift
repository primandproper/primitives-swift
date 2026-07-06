import Foundation

/// One result row, the port's replacement for Go's `database.Scanner`/`sql.Row` seam. Columns are
/// available positionally (`row[0]`) or by name (`row["id"]`), with typed accessors that fold NULL and
/// type mismatches to `nil` rather than trapping.
public struct Row: Sendable, Equatable {
  /// The result column names, in selection order.
  public let columns: [String]
  /// The result values, index-aligned with ``columns``.
  public let values: [SQLValue]

  private let indexByName: [String: Int]

  init(columns: [String], values: [SQLValue]) {
    self.columns = columns
    self.values = values
    // Last-writer-wins on duplicate column names, matching how a positional scan would see them.
    var index: [String: Int] = [:]
    for (i, name) in columns.enumerated() { index[name] = i }
    self.indexByName = index
  }

  /// Positional access. Out-of-range indices return `nil`.
  public subscript(_ index: Int) -> SQLValue? {
    values.indices.contains(index) ? values[index] : nil
  }

  /// Access by column name. Unknown names return `nil`.
  public subscript(_ name: String) -> SQLValue? {
    indexByName[name].map { values[$0] }
  }

  public func string(_ name: String) -> String? { self[name]?.stringValue }
  public func int(_ name: String) -> Int64? { self[name]?.intValue }
  public func double(_ name: String) -> Double? { self[name]?.doubleValue }
  public func bool(_ name: String) -> Bool? { self[name]?.boolValue }
  public func blob(_ name: String) -> [UInt8]? { self[name]?.blobValue }

  public static func == (lhs: Row, rhs: Row) -> Bool {
    lhs.columns == rhs.columns && lhs.values == rhs.values
  }
}
