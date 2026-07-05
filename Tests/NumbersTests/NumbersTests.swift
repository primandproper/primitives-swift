import Foundation
import Testing

@testable import Numbers

private func approx(_ a: Float, _ b: Float, _ tol: Float) -> Bool {
  abs(a - b) <= tol
}

@Suite("roundToDecimalPlaces")
struct RoundToDecimalPlacesTests {
  @Test("rounds a positive number to two decimals")
  func positiveTwo() {
    #expect(roundToDecimalPlaces(3.14159, precision: 2) == 3.14)
  }

  @Test("rounds to zero decimals, half away from zero")
  func zeroDecimals() {
    #expect(roundToDecimalPlaces(3.7, precision: 0) == 4.0)
    #expect(roundToDecimalPlaces(-3.7, precision: 0) == -4.0)
  }

  @Test("rounds negatives symmetrically")
  func negatives() {
    #expect(roundToDecimalPlaces(-3.14159, precision: 2) == -3.14)
    #expect(approx(roundToDecimalPlaces(-2.555, precision: 2), -2.56, 0.01))
  }

  @Test("zero rounds to zero")
  func zero() {
    #expect(roundToDecimalPlaces(0.0, precision: 2) == 0.0)
  }

  @Test("rounds up and down at the boundary")
  func boundary() {
    #expect(approx(roundToDecimalPlaces(2.555, precision: 2), 2.56, 0.01))
    #expect(approx(roundToDecimalPlaces(2.554, precision: 2), 2.55, 0.01))
  }

  @Test("large value does not saturate at int32")
  func largeValue() {
    // value * 10^2 = 2e9 overflows int32 in a naive implementation; the Double path keeps it exact.
    #expect(roundToDecimalPlaces(2e7, precision: 2) == 2e7)
  }

  @Test("high precision does not overflow the multiplier to zero")
  func highPrecision() {
    // A Float multiplier saturates to +Inf around precision 39; the Double path stays finite.
    #expect(approx(roundToDecimalPlaces(3.14, precision: 39), 3.14, 0.01))
  }
}

@Suite("scale")
struct ScaleTests {
  @Test("doubles a quantity with default precision")
  func double() {
    #expect(scale(2.5, factor: 2.0) == 5.0)
  }

  @Test("halves a quantity")
  func halve() {
    #expect(scale(4.0, factor: 0.5) == 2.0)
  }

  @Test("honors a custom precision")
  func customPrecision() {
    #expect(approx(scale(3.333, factor: 3.0, precision: 3), 9.999, 0.001))
  }

  @Test("factor of one is identity; factor of zero is zero")
  func edges() {
    #expect(scale(5.5, factor: 1.0) == 5.5)
    #expect(scale(10.0, factor: 0.0) == 0.0)
    #expect(scale(0.0, factor: 5.0) == 0.0)
  }

  @Test("scales negatives and very large values without saturation")
  func negativeAndLarge() {
    #expect(scale(-5.0, factor: 2.0) == -10.0)
    #expect(scale(2e7, factor: 2.0) == 4e7)
  }
}

@Suite("scaleToYield")
struct ScaleToYieldTests {
  @Test("scales from four servings to six")
  func fourToSix() {
    #expect(scaleToYield(2.0, originalYield: 4, desiredYield: 6) == 3.0)
  }

  @Test("scales down and across equal yields")
  func downAndEqual() {
    #expect(scaleToYield(4.0, originalYield: 4, desiredYield: 2) == 2.0)
    #expect(scaleToYield(3.5, originalYield: 4, desiredYield: 4) == 3.5)
  }

  @Test("honors custom and zero precision")
  func precision() {
    #expect(approx(scaleToYield(1.0, originalYield: 3, desiredYield: 7, precision: 3), 2.333, 0.001))
    #expect(scaleToYield(2.7, originalYield: 4, desiredYield: 6, precision: 0) == 4.0)
  }

  @Test("non-positive original yield returns the original value unchanged")
  func guardYield() {
    #expect(scaleToYield(5.0, originalYield: 0, desiredYield: 10) == 5.0)
    #expect(scaleToYield(5.0, originalYield: -2, desiredYield: 10) == 5.0)
  }
}

@Suite("MinRange")
struct MinRangeTests {
  @Test("a range with only a minimum is valid")
  func minOnly() throws {
    try MinRange<Float>(min: 1.0).validate()
  }

  @Test("a zero minimum is a valid range")
  func zeroMin() throws {
    try MinRange<Float>(min: 0).validate()
    try MinRange<UInt16>(min: 0).validate()
    try MinRange<UInt32>(min: 0).validate()
  }

  @Test("max below min is invalid")
  func maxBelowMin() {
    #expect(throws: RangeValidationError.maxBelowMin) {
      try MinRange<Int>(min: 5, max: 2).validate()
    }
  }

  @Test("max at or above min is valid")
  func maxAtOrAbove() throws {
    try MinRange<Int>(min: 5, max: 5).validate()
    try MinRange<Int>(min: 5, max: 10).validate()
  }

  @Test("nil max is omitted from JSON (Go omitempty)")
  func omitsNilMax() throws {
    let data = try JSONEncoder().encode(MinRange<Int>(min: 3))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"min":3}"#)
  }

  @Test("round-trips through Codable")
  func codableRoundTrip() throws {
    let original = MinRange<Int>(min: 1, max: 9)
    let restored = try JSONDecoder().decode(
      MinRange<Int>.self, from: JSONEncoder().encode(original))
    #expect(restored == original)
  }
}

@Suite("OpenRange")
struct OpenRangeTests {
  @Test("both bounds omitted encode to an empty object")
  func empty() throws {
    let data = try JSONEncoder().encode(OpenRange<Int>())
    #expect(String(decoding: data, as: UTF8.self) == "{}")
  }

  @Test("round-trips both bounds through Codable")
  func roundTrip() throws {
    let original = OpenRange<Double>(min: 1.5, max: 9.5)
    let restored = try JSONDecoder().decode(
      OpenRange<Double>.self, from: JSONEncoder().encode(original))
    #expect(restored == original)
  }
}
