/// A typed, `Sendable` observation value shared by the span, log, and operation surfaces.
///
/// Ported in spirit from OpenTelemetry's attribute value model: the small set of scalar and
/// homogeneous-array cases an exporter can represent natively. Making the value `Sendable` (rather
/// than the old `Any`) is what lets `LiveOperation` carry it across the field-storage lock without
/// the pre-stringify dance the earlier lost-update fix required — see ``LiveOperation/set(_:_:)``.
public enum AttributeValue: Sendable, Equatable {
  case string(String)
  case int(Int64)
  case double(Double)
  case bool(Bool)
  case stringArray([String])
  case intArray([Int64])
  case doubleArray([Double])
  case boolArray([Bool])

  /// The string form used by the stringifying backends (`OSLogLogger` fields, signpost messages,
  /// the recording double). Scalars render exactly as `String(describing:)` did before this type
  /// existed, so existing value assertions keep passing; arrays render as bracketed, comma-joined
  /// lists.
  public var rendered: String {
    switch self {
    case .string(let v): return v
    case .int(let v): return String(v)
    case .double(let v): return String(v)
    case .bool(let v): return String(v)
    case .stringArray(let v): return "[" + v.joined(separator: ", ") + "]"
    case .intArray(let v): return "[" + v.map { String($0) }.joined(separator: ", ") + "]"
    case .doubleArray(let v): return "[" + v.map { String($0) }.joined(separator: ", ") + "]"
    case .boolArray(let v): return "[" + v.map { String($0) }.joined(separator: ", ") + "]"
    }
  }
}

// MARK: - Literal sugar

// Enables mixed-type dictionary literals at the `setValues`/`withValues` call sites, e.g.
// `op.setValues(["count": 3, "name": "abc", "ok": true])`.
extension AttributeValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
}
extension AttributeValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self = .int(value) }
}
extension AttributeValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) { self = .double(value) }
}
extension AttributeValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

// MARK: - Bridging

/// A type that can be recorded as an ``AttributeValue``. The scalar setters accept any conformer, so
/// `op.set(Keys.responseStatus, http.statusCode)` (an `Int` variable) and `op.set("name", "abc")`
/// (a `String` literal) both work without an explicit `.int`/`.string` at the call site.
///
/// `AttributeValue` itself deliberately does **not** conform: that keeps the generic sugar
/// (`set(_:_: some AttributeRepresentable)`) from ever satisfying the concrete
/// `set(_:_: AttributeValue)` protocol requirement, which would recurse forever. A conformer that
/// forgets to implement the concrete requirement therefore fails to compile instead of stack-overflowing.
public protocol AttributeRepresentable {
  var attributeValue: AttributeValue { get }
}

extension String: AttributeRepresentable {
  public var attributeValue: AttributeValue { .string(self) }
}
extension Int: AttributeRepresentable {
  public var attributeValue: AttributeValue { .int(Int64(self)) }
}
extension Int64: AttributeRepresentable {
  public var attributeValue: AttributeValue { .int(self) }
}
extension Double: AttributeRepresentable {
  public var attributeValue: AttributeValue { .double(self) }
}
extension Bool: AttributeRepresentable {
  public var attributeValue: AttributeValue { .bool(self) }
}
extension Array: AttributeRepresentable where Element == String {
  public var attributeValue: AttributeValue { .stringArray(self) }
}
