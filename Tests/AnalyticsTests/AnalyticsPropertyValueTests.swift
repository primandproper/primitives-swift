import Foundation
import Testing

@testable import Analytics

@Suite("AnalyticsPropertyValue")
struct AnalyticsPropertyValueTests {
  @Test("literal conveniences build the expected cases")
  func literals() {
    let value: [String: AnalyticsPropertyValue] = [
      "name": "swift",
      "count": 3,
      "ratio": 1.5,
      "active": true,
      "missing": nil,
      "tags": ["a", "b"],
      "nested": ["k": "v"],
    ]

    #expect(value["name"] == .string("swift"))
    #expect(value["count"] == .number(3))
    #expect(value["ratio"] == .number(1.5))
    #expect(value["active"] == .bool(true))
    #expect(value["missing"] == .null)
    #expect(value["tags"] == .array([.string("a"), .string("b")]))
    #expect(value["nested"] == .object(["k": .string("v")]))
  }

  @Test("round-trips every case through JSON")
  func roundTrip() throws {
    let original: [String: AnalyticsPropertyValue] = [
      "string": .string("value"),
      "number": .number(42),
      "bool": .bool(false),
      "null": .null,
      "array": .array([.number(1), .string("two")]),
      "object": .object(["k": .bool(true)]),
    ]

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode([String: AnalyticsPropertyValue].self, from: data)

    #expect(decoded == original)
  }

  @Test("decodes the Go JSON wire shape (map[string]any)")
  func decodesGoShape() throws {
    let json = Data(#"{"plan":"pro","seats":3,"trial":false,"extra":null}"#.utf8)
    let decoded = try JSONDecoder().decode([String: AnalyticsPropertyValue].self, from: json)

    #expect(decoded["plan"] == .string("pro"))
    #expect(decoded["seats"] == .number(3))
    #expect(decoded["trial"] == .bool(false))
    #expect(decoded["extra"] == .null)
  }
}
