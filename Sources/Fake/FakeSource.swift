import RandomKit

/// Abstracts the randomness backing ``Fake``'s and ``FakeGenerator``'s generation logic (see
/// `FakeEngine.swift`), so the exact same corpus-composition code can run against either the
/// default, non-deterministic source (``SystemFakeSource``) or a seeded, reproducible one
/// (``SeededFakeSource``).
protocol FakeSource {
  /// Picks a random element from `array`, or `nil` if it is empty.
  mutating func pick<T>(from array: [T]) -> T?
  /// Returns a random `Int` within `range`.
  mutating func int(in range: ClosedRange<Int>) -> Int
  /// Returns a random `Double` within `range`.
  mutating func double(in range: ClosedRange<Double>) -> Double
  /// Returns a random `Bool`.
  mutating func bool() -> Bool
}

/// The default ``FakeSource``: non-deterministic, backed by the system's random generator.
///
/// Corpus picks route through ``RandomKit``'s `randomElement(from:)` — the same convenience picker
/// RandomKit's own documentation calls out as appropriate for non-secret selection (see
/// `RandomKit/Slices.swift`). Numeric ranges use the standard library's `random(in:)`, which, like
/// RandomKit's picker, draws from `SystemRandomNumberGenerator` rather than a naive
/// `Math.random`-style generator. Fake data has no secrecy requirement, so `StandardGenerator`'s
/// cryptographic strength is unnecessary overhead here.
struct SystemFakeSource: FakeSource {
  mutating func pick<T>(from array: [T]) -> T? {
    randomElement(from: array)
  }

  mutating func int(in range: ClosedRange<Int>) -> Int {
    Int.random(in: range)
  }

  mutating func double(in range: ClosedRange<Double>) -> Double {
    Double.random(in: range)
  }

  mutating func bool() -> Bool {
    Bool.random()
  }
}

/// A deterministic ``FakeSource`` for reproducible fixtures (e.g. SwiftUI previews or golden
/// tests). Wraps a seeded ``SplitMix64`` generator — RandomKit has no seeded API of its own (its
/// generators are either cryptographic and unseeded, by design, or the plain
/// `SystemRandomNumberGenerator`-backed picker), so reproducibility is layered on top here using
/// the standard library's `RandomNumberGenerator` protocol rather than any ad hoc generator.
struct SeededFakeSource: FakeSource {
  private var rng: SplitMix64

  init(seed: UInt64) {
    rng = SplitMix64(seed: seed)
  }

  mutating func pick<T>(from array: [T]) -> T? {
    array.randomElement(using: &rng)
  }

  mutating func int(in range: ClosedRange<Int>) -> Int {
    Int.random(in: range, using: &rng)
  }

  mutating func double(in range: ClosedRange<Double>) -> Double {
    Double.random(in: range, using: &rng)
  }

  mutating func bool() -> Bool {
    Bool.random(using: &rng)
  }
}
