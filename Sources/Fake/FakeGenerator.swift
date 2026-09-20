import Foundation

/// A seeded, reproducible counterpart to ``Fake``, for callers that need the *same* fixture data
/// every time — most notably SwiftUI `#Preview` bodies, which re-render on every canvas refresh
/// and look broken if the sample data reshuffles each time.
///
/// ```swift
/// var preview = FakeGenerator(seed: 1)
/// let user = User(name: preview.fullName(), email: preview.email())
/// ```
///
/// Every method mirrors a ``Fake`` static function, driven by the same shared generation logic in
/// `FakeEngine.swift`, but backed by a seeded ``SeededFakeSource`` instead of the system's
/// non-deterministic one — so two generators constructed with the same seed and driven through the
/// same call sequence always produce identical output.
///
/// **Where seeding is not feasible.** ``uuid()`` delegates to `Foundation.UUID`, which exposes no
/// seedable API, so it remains non-deterministic even on a seeded generator. Every other generator
/// here is fully reproducible — including ``opaqueID()``, which replaced an `xid()` that was not.
public struct FakeGenerator: Sendable {
  private var source: SeededFakeSource

  /// Creates a generator that will always produce the same sequence of values for a given `seed`.
  public init(seed: UInt64) {
    source = SeededFakeSource(seed: seed)
  }

  /// A reproducible first name from a small embedded corpus.
  public mutating func firstName() -> String {
    FakeEngine.firstName(using: &source)
  }

  /// A reproducible last name from a small embedded corpus.
  public mutating func lastName() -> String {
    FakeEngine.lastName(using: &source)
  }

  /// A reproducible "First Last" full name.
  public mutating func fullName() -> String {
    FakeEngine.fullName(using: &source)
  }

  /// A reproducible username of the form `first.lastNNN`.
  public mutating func username() -> String {
    FakeEngine.username(using: &source)
  }

  /// A reproducible, syntactically valid email address at a reserved-for-testing domain.
  public mutating func email() -> String {
    FakeEngine.email(using: &source)
  }

  /// A single, reproducible lorem-ipsum word.
  public mutating func word() -> String {
    FakeEngine.word(using: &source)
  }

  /// A reproducible, capitalized, period-terminated lorem-ipsum sentence. Defaults to a random
  /// (but still seed-reproducible) length between 6 and 12 words when `wordCount` is `nil`.
  public mutating func sentence(wordCount: Int? = nil) -> String {
    let count = wordCount ?? source.int(in: 6...12)
    return FakeEngine.sentence(wordCount: count, using: &source)
  }

  /// A reproducible lorem-ipsum paragraph. Defaults to a random (but still seed-reproducible)
  /// length between 3 and 6 sentences when `sentenceCount` is `nil`.
  public mutating func paragraph(sentenceCount: Int? = nil) -> String {
    let count = sentenceCount ?? source.int(in: 3...6)
    return FakeEngine.paragraph(sentenceCount: count, using: &source)
  }

  /// A reproducible US-shaped phone number, e.g. `"(415) 555-0142"`.
  public mutating func phoneNumber() -> String {
    FakeEngine.phoneNumber(using: &source)
  }

  /// A reproducible `https://` URL built from a lorem word and a common top-level domain.
  public mutating func url() -> String {
    FakeEngine.url(using: &source)
  }

  /// A random RFC 4122 UUID string. Not seed-reproducible — see the type-level discussion above.
  public func uuid() -> String {
    UUID().uuidString
  }

  /// A reproducible 20-character lowercase base32-hex string, shaped like a server-issued
  /// ID without being one. Unlike the `xid()` this replaces, it is drawn from the seeded
  /// source, so a seeded generator reproduces it.
  public mutating func opaqueID() -> String {
    FakeEngine.opaqueID(using: &source)
  }

  /// A reproducible random `Bool`.
  public mutating func bool() -> Bool {
    source.bool()
  }

  /// A reproducible random `Int` within `range` (defaults to `0...100`).
  public mutating func int(in range: ClosedRange<Int> = 0...100) -> Int {
    source.int(in: range)
  }

  /// A reproducible random `Double` within `range` (defaults to `0...1`).
  public mutating func double(in range: ClosedRange<Double> = 0...1) -> Double {
    source.double(in: range)
  }

  /// A reproducible random `Date` within `range` (defaults to the last 10 years, up to now).
  public mutating func date(in range: ClosedRange<Date> = Fake.defaultDateRange) -> Date {
    FakeEngine.date(in: range, using: &source)
  }

  /// Picks a reproducible random element from `array`, or `nil` if it is empty.
  public mutating func pick<T>(from array: [T]) -> T? {
    source.pick(from: array)
  }
}
