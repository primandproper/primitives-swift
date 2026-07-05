import Foundation

/// Numeric rounding and scaling utilities, ported from platform-go's `numbers/numbers.go`.
///
/// Go operates on `float32` throughout, so we use Swift's `Float`. The rounding is performed in
/// `Double` for the same reason Go does it in `float64`: large values otherwise saturate, and high
/// precisions overflow the multiplier. `math.Round` rounds half away from zero, which maps to
/// `FloatingPointRoundingRule.toNearestOrAwayFromZero`.

/// Rounds `value` to `precision` decimal places, half away from zero. Mirrors Go's
/// `RoundToDecimalPlaces`.
public func roundToDecimalPlaces(_ value: Float, precision: UInt8) -> Float {
  let multiplier = pow(10.0, Double(precision))
  return Float((Double(value) * multiplier).rounded(.toNearestOrAwayFromZero) / multiplier)
}

/// Multiplies `value` by `factor` and rounds to `precision` decimal places (default 2). Mirrors
/// Go's `Scale`, whose optional variadic precision becomes a defaulted parameter here.
public func scale(_ value: Float, factor: Float, precision: UInt8 = 2) -> Float {
  roundToDecimalPlaces(value * factor, precision: precision)
}

/// Scales `originalValue` from `originalYield` units to `desiredYield` units, rounded to
/// `precision` decimal places (default 2). A non-positive `originalYield` returns `originalValue`
/// unchanged, matching Go's `ScaleToYield` guard against divide-by-zero.
public func scaleToYield(
  _ originalValue: Float,
  originalYield: Int,
  desiredYield: Int,
  precision: UInt8 = 2
) -> Float {
  guard originalYield > 0 else { return originalValue }
  let factor = Float(desiredYield) / Float(originalYield)
  return scale(originalValue, factor: factor, precision: precision)
}
