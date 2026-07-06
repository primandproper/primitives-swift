import Foundation
import Identifiers
import RandomKit

/// # Fake
///
/// Hand-rolled, no-dependency fixture generation for tests and SwiftUI previews.
///
/// **This is a greenfield port, not a line-by-line one.** platform-go's `fake` package is a
/// 46-line reflection-based generic faker (`BuildFake[X]`, `MustBuildFake[X]`,
/// `BuildFakeForTest[X]`) that hands an arbitrary struct pointer to `go-faker/faker` and
/// `brianvoe/gofakeit`, plus a `BuildFakeTime()` helper. Swift has no equivalent
/// runtime-reflection-driven "populate every field of any struct" facility (nor would leaning on
/// `Mirror` for *writing* values be idiomatic), so instead of reimplementing that mechanism, this
/// module ships the same *purpose* — realistic fixture data for tests and previews — as a
/// dependency-free, corpus-based namespace with explicit generators (names, emails, lorem text,
/// phone numbers, URLs, identifiers, numbers, dates, and random-pick). Callers ask for exactly the
/// shape of fake value they need rather than reflecting one out of a type.
///
/// Two entry points share the same generation logic (`FakeEngine.swift`):
///   * ``Fake`` — static, non-deterministic helpers, for ordinary test fixtures.
///   * ``FakeGenerator`` — a seeded, reproducible generator, for SwiftUI preview data that should
///     look the same on every render.
///
/// Randomness always goes through ``RandomKit`` or the standard library's
/// `RandomNumberGenerator`-based APIs (see `FakeSource.swift`) — never a hand-rolled
/// `Math.random`-style generator.
public enum Fake: Sendable {
  /// A random first name from a small embedded corpus.
  public static func firstName() -> String {
    var source = SystemFakeSource()
    return FakeEngine.firstName(using: &source)
  }

  /// A random last name from a small embedded corpus.
  public static func lastName() -> String {
    var source = SystemFakeSource()
    return FakeEngine.lastName(using: &source)
  }

  /// A random "First Last" full name.
  public static func fullName() -> String {
    var source = SystemFakeSource()
    return FakeEngine.fullName(using: &source)
  }

  /// A random username of the form `first.lastNNN`.
  public static func username() -> String {
    var source = SystemFakeSource()
    return FakeEngine.username(using: &source)
  }

  /// A random, syntactically valid email address at one of a handful of reserved-for-testing
  /// domains (`example.com` and friends — never a real, deliverable mailbox).
  public static func email() -> String {
    var source = SystemFakeSource()
    return FakeEngine.email(using: &source)
  }

  /// A single lorem-ipsum word.
  public static func word() -> String {
    var source = SystemFakeSource()
    return FakeEngine.word(using: &source)
  }

  /// A capitalized, period-terminated lorem-ipsum sentence. Defaults to a random length between 6
  /// and 12 words when `wordCount` is `nil`.
  public static func sentence(wordCount: Int? = nil) -> String {
    var source = SystemFakeSource()
    let count = wordCount ?? source.int(in: 6...12)
    return FakeEngine.sentence(wordCount: count, using: &source)
  }

  /// A lorem-ipsum paragraph. Defaults to a random length between 3 and 6 sentences when
  /// `sentenceCount` is `nil`.
  public static func paragraph(sentenceCount: Int? = nil) -> String {
    var source = SystemFakeSource()
    let count = sentenceCount ?? source.int(in: 3...6)
    return FakeEngine.paragraph(sentenceCount: count, using: &source)
  }

  /// A random US-shaped phone number, e.g. `"(415) 555-0142"`.
  public static func phoneNumber() -> String {
    var source = SystemFakeSource()
    return FakeEngine.phoneNumber(using: &source)
  }

  /// A random `https://` URL built from a lorem word and a common top-level domain.
  public static func url() -> String {
    var source = SystemFakeSource()
    return FakeEngine.url(using: &source)
  }

  /// A random RFC 4122 UUID string. Delegates to `Foundation.UUID`.
  public static func uuid() -> String {
    UUID().uuidString
  }

  /// A random 20-character xid string. Delegates to ``Identifiers/Identifier/new()``.
  public static func xid() -> String {
    Identifier.new()
  }

  /// A random `Bool`.
  public static func bool() -> Bool {
    var source = SystemFakeSource()
    return source.bool()
  }

  /// A random `Int` within `range` (defaults to `0...100`).
  public static func int(in range: ClosedRange<Int> = 0...100) -> Int {
    var source = SystemFakeSource()
    return source.int(in: range)
  }

  /// A random `Double` within `range` (defaults to `0...1`).
  public static func double(in range: ClosedRange<Double> = 0...1) -> Double {
    var source = SystemFakeSource()
    return source.double(in: range)
  }

  /// A random `Date` within `range` (defaults to the last 10 years, up to now).
  public static func date(in range: ClosedRange<Date> = defaultDateRange) -> Date {
    var source = SystemFakeSource()
    return FakeEngine.date(in: range, using: &source)
  }

  /// Picks a random element from `array`, or `nil` if it is empty. A thin, discoverable
  /// `Fake`-namespaced wrapper over ``RandomKit``'s `randomElement(from:)`.
  public static func pick<T>(from array: [T]) -> T? {
    randomElement(from: array)
  }

  /// The last 10 years, up to the moment this is evaluated. Recomputed on every call so repeated
  /// use of the `date(in:)` default keeps tracking "now". Public because it is used as a default
  /// argument value from ``FakeGenerator/date(in:)`` too, and default-argument expressions must be
  /// at least as visible as the function they default for.
  public static var defaultDateRange: ClosedRange<Date> {
    let now = Date()
    let tenYears: TimeInterval = 10 * 365 * 24 * 60 * 60
    return now.addingTimeInterval(-tenYears)...now
  }
}
