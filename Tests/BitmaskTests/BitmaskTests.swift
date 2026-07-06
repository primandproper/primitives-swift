import Foundation
import Testing

@testable import Bitmask

private let permRead: UInt8 = 1 << 0
private let permWrite: UInt8 = 1 << 1
private let permDelete: UInt8 = 1 << 2
private let permAdmin: UInt8 = 1 << 3

@Suite("Bitmask construction")
struct ConstructionTests {
  @Test("empty mask has zero value and is empty")
  func empty() {
    let mask = Bitmask<UInt8>()
    #expect(mask.value == 0)
    #expect(mask.isEmpty)
  }

  @Test("single and multiple flags OR-combine")
  func flags() {
    #expect(Bitmask(permRead).value == permRead)
    #expect(Bitmask(permRead, permWrite).value == permRead | permWrite)
  }

  @Test("duplicate flags are idempotent")
  func duplicates() {
    #expect(Bitmask(permRead, permRead).value == permRead)
  }

  @Test("fromValue wraps a raw value")
  func fromValue() {
    let mask = Bitmask(value: UInt8(5))
    #expect(mask.has(permRead))
    #expect(mask.has(permDelete))
    #expect(!mask.has(permWrite))
  }
}

@Suite("Bitmask mutation returns new values")
struct MutationTests {
  @Test("set adds flags without mutating the original")
  func set() {
    let base = Bitmask<UInt8>()
    let updated = base.set(permRead, permWrite)
    #expect(updated.has(permRead))
    #expect(updated.has(permWrite))
    #expect(base.isEmpty)
  }

  @Test("clear removes flags without mutating the original")
  func clear() {
    let base = Bitmask(permRead, permWrite)
    let updated = base.clear(permWrite)
    #expect(updated.has(permRead))
    #expect(!updated.has(permWrite))
    #expect(base.has(permWrite))
  }

  @Test("toggle flips flags")
  func toggle() {
    #expect(Bitmask<UInt8>().toggle(permRead).has(permRead))
    #expect(!Bitmask(permRead).toggle(permRead).has(permRead))
    let mixed = Bitmask(permRead).toggle(permRead, permWrite)
    #expect(!mixed.has(permRead))
    #expect(mixed.has(permWrite))
  }

  @Test("chained operations each yield independent values")
  func chained() {
    let a = Bitmask(permRead)
    let b = a.set(permWrite)
    let c = b.clear(permRead)
    #expect(a.value == permRead)
    #expect(b.value == permRead | permWrite)
    #expect(c.value == permWrite)
  }
}

@Suite("Bitmask predicates")
struct PredicateTests {
  @Test("has is true for set flags, false for unset and zero")
  func has() {
    let mask = Bitmask(permRead, permWrite)
    #expect(mask.has(permRead))
    #expect(!mask.has(permDelete))
    #expect(!mask.has(0))
  }

  @Test("hasAll requires every flag and rejects empty/zero input")
  func hasAll() {
    let mask = Bitmask(permRead, permWrite, permDelete)
    #expect(mask.hasAll(permRead, permWrite))
    #expect(!Bitmask(permRead).hasAll(permRead, permWrite))
    #expect(!mask.hasAll())
    #expect(!mask.hasAll(0))
  }

  @Test("hasAny requires at least one flag")
  func hasAny() {
    let mask = Bitmask(permRead)
    #expect(mask.hasAny(permRead, permWrite))
    #expect(!mask.hasAny(permWrite, permDelete))
    #expect(!mask.hasAny())
  }

  @Test("isEmpty and count reflect the set bits")
  func emptyAndCount() {
    #expect(Bitmask<UInt8>().isEmpty)
    #expect(Bitmask<UInt8>().count == 0)
    #expect(Bitmask(permRead).count == 1)
    #expect(Bitmask(permRead, permWrite, permDelete).count == 3)
    #expect(Bitmask(value: ~UInt8(0)).count == 8)
  }
}

@Suite("Bitmask set algebra")
struct SetAlgebraTests {
  @Test("union combines both masks")
  func union() {
    let result = Bitmask(permRead).union(Bitmask(permWrite))
    #expect(result.has(permRead))
    #expect(result.has(permWrite))
  }

  @Test("intersect keeps only shared flags")
  func intersect() {
    let result = Bitmask(permRead, permWrite).intersect(Bitmask(permWrite, permDelete))
    #expect(!result.has(permRead))
    #expect(result.has(permWrite))
    #expect(!result.has(permDelete))
  }

  @Test("difference removes the other's flags")
  func difference() {
    let result = Bitmask(permRead, permWrite, permDelete).difference(Bitmask(permWrite))
    #expect(result.has(permRead))
    #expect(!result.has(permWrite))
    #expect(result.has(permDelete))
    #expect(Bitmask(permRead, permWrite).difference(Bitmask(permRead, permWrite)).isEmpty)
  }
}

@Suite("Bitmask description")
struct DescriptionTests {
  @Test("renders a zero-padded binary string at the type's width")
  func binary() {
    #expect(Bitmask<UInt8>().description == "00000000")
    #expect(Bitmask(permRead).description == "00000001")
    #expect(Bitmask(permRead, permWrite).description == "00000011")
    #expect(Bitmask(value: ~UInt8(0)).description == "11111111")
  }

  @Test("width tracks the underlying integer type")
  func widths() {
    #expect(Bitmask<UInt16>(1).description == "0000000000000001")
    #expect(Bitmask<UInt16>(1, 4).description == "0000000000000101")
    #expect(Bitmask(UInt32(1)).description.count == 32)
  }
}

@Suite("Bitmask Codable")
struct CodableTests {
  @Test("marshals as a bare number, including as a struct field")
  func marshal() throws {
    #expect(
      String(decoding: try JSONEncoder().encode(Bitmask(permRead, permWrite)), as: UTF8.self) == "3"
    )
    #expect(String(decoding: try JSONEncoder().encode(Bitmask<UInt8>()), as: UTF8.self) == "0")

    struct Wrapper: Codable { var perms: Bitmask<UInt8> }
    let data = try JSONEncoder().encode(Wrapper(perms: Bitmask(permRead, permDelete)))
    #expect(String(decoding: data, as: UTF8.self) == #"{"perms":5}"#)
  }

  @Test("unmarshals a bare number")
  func unmarshal() throws {
    let mask = try JSONDecoder().decode(Bitmask<UInt8>.self, from: Data("3".utf8))
    #expect(mask.has(permRead))
    #expect(mask.has(permWrite))
  }

  @Test("rejects values that do not fit the type width")
  func widthOverflow() {
    // testPerm is UInt8; 511 must error rather than truncating to 255.
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(Bitmask<UInt8>.self, from: Data("511".utf8))
    }
  }

  @Test("rejects negative values")
  func negative() {
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(Bitmask<UInt8>.self, from: Data("-1".utf8))
    }
  }

  @Test("accepts the maximum value for the type width")
  func maxValue() throws {
    let mask = try JSONDecoder().decode(Bitmask<UInt8>.self, from: Data("255".utf8))
    #expect(mask.value == 255)
  }

  @Test("round-trips through encode/decode")
  func roundTrip() throws {
    let original = Bitmask(permRead, permWrite, permAdmin)
    let restored = try JSONDecoder().decode(
      Bitmask<UInt8>.self, from: JSONEncoder().encode(original))
    #expect(restored.value == original.value)
  }
}

@Suite("Bitmask wider types")
struct WiderTypeTests {
  @Test("uint32 counts and widths behave")
  func uint32() {
    #expect(Bitmask(value: UInt32(0b1111_0000_0000_1111)).count == 8)
    #expect(Bitmask(UInt32(1)).description.count == 32)
  }
}
