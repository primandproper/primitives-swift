import Foundation
import Testing

@testable import FeatureFlags

@Suite("FlagValue")
struct FlagValueTests {
  @Test("typed accessors return the payload for a matching case")
  func accessorsMatch() {
    #expect(FlagValue.string("hi").stringValue == "hi")
    #expect(FlagValue.number(3.14).doubleValue == 3.14)
    #expect(FlagValue.bool(true).boolValue == true)
    #expect(FlagValue.array([.bool(true)]).arrayValue == [.bool(true)])
    #expect(FlagValue.object(["k": "v"]).objectValue == ["k": "v"])
  }

  @Test("typed accessors return nil for a non-matching case")
  func accessorsMismatch() {
    #expect(FlagValue.string("hi").doubleValue == nil)
    #expect(FlagValue.number(1).stringValue == nil)
    #expect(FlagValue.null.boolValue == nil)
    #expect(FlagValue.bool(true).arrayValue == nil)
    #expect(FlagValue.array([]).objectValue == nil)
  }

  @Test("literal conformances build the expected cases")
  func literals() {
    let string: FlagValue = "hello"
    let bool: FlagValue = true
    let number: FlagValue = 42
    let float: FlagValue = 3.5
    let null: FlagValue = nil
    let array: FlagValue = ["a", "b"]
    let object: FlagValue = ["key": "value"]

    #expect(string == .string("hello"))
    #expect(bool == .bool(true))
    #expect(number == .number(42))
    #expect(float == .number(3.5))
    #expect(null == .null)
    #expect(array == .array([.string("a"), .string("b")]))
    #expect(object == .object(["key": .string("value")]))
  }

  @Test("decodes every JSON shape")
  func decodesAllShapes() throws {
    let decoder = JSONDecoder()

    #expect(try decoder.decode(FlagValue.self, from: Data(#""hi""#.utf8)) == .string("hi"))
    #expect(try decoder.decode(FlagValue.self, from: Data("3.14".utf8)) == .number(3.14))
    #expect(try decoder.decode(FlagValue.self, from: Data("true".utf8)) == .bool(true))
    #expect(try decoder.decode(FlagValue.self, from: Data("null".utf8)) == .null)
    #expect(
      try decoder.decode(FlagValue.self, from: Data("[1,2]".utf8))
        == .array([.number(1), .number(2)]))
    #expect(
      try decoder.decode(FlagValue.self, from: Data(#"{"key":"value"}"#.utf8))
        == .object(["key": .string("value")]))
  }

  @Test("round-trips through JSON encode/decode")
  func roundTrip() throws {
    let original: FlagValue = ["key": ["nested": true, "count": 2], "list": [1, "two", nil]]
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FlagValue.self, from: encoded)
    #expect(decoded == original)
  }
}
