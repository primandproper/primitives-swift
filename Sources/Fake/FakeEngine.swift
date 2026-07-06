import Foundation

/// The shared corpus-composition logic behind ``Fake`` and ``FakeGenerator``.
///
/// Every function here is generic over ``FakeSource`` so the exact same code produces either
/// non-deterministic data (when called with a ``SystemFakeSource``) or reproducible data (when
/// called with a ``SeededFakeSource``) — the two public entry points differ only in which source
/// they hand in.
enum FakeEngine {
  static func firstName<S: FakeSource>(using source: inout S) -> String {
    source.pick(from: FakeCorpus.firstNames) ?? "Jordan"
  }

  static func lastName<S: FakeSource>(using source: inout S) -> String {
    source.pick(from: FakeCorpus.lastNames) ?? "Smith"
  }

  static func fullName<S: FakeSource>(using source: inout S) -> String {
    "\(firstName(using: &source)) \(lastName(using: &source))"
  }

  static func username<S: FakeSource>(using source: inout S) -> String {
    let first = firstName(using: &source).lowercased()
    let last = lastName(using: &source).lowercased()
    let suffix = source.int(in: 1...999)
    return "\(first).\(last)\(suffix)"
  }

  static func email<S: FakeSource>(using source: inout S) -> String {
    let handle = username(using: &source)
    let domain = source.pick(from: FakeCorpus.emailDomains) ?? "example.com"
    return "\(handle)@\(domain)"
  }

  static func word<S: FakeSource>(using source: inout S) -> String {
    source.pick(from: FakeCorpus.loremWords) ?? "lorem"
  }

  static func sentence<S: FakeSource>(wordCount: Int, using source: inout S) -> String {
    let count = max(1, wordCount)
    let words = (0..<count).map { _ in word(using: &source) }
    let joined = words.joined(separator: " ")
    let capitalized = joined.prefix(1).uppercased() + joined.dropFirst()
    return capitalized + "."
  }

  static func paragraph<S: FakeSource>(sentenceCount: Int, using source: inout S) -> String {
    let count = max(1, sentenceCount)
    let sentences = (0..<count).map { _ in
      sentence(wordCount: source.int(in: 4...12), using: &source)
    }
    return sentences.joined(separator: " ")
  }

  static func phoneNumber<S: FakeSource>(using source: inout S) -> String {
    let area = source.int(in: 200...999)
    let exchange = source.int(in: 200...999)
    let line = source.int(in: 0...9999)
    return String(format: "(%03d) %03d-%04d", area, exchange, line)
  }

  static func url<S: FakeSource>(using source: inout S) -> String {
    let host = word(using: &source)
    let tld = source.pick(from: FakeCorpus.topLevelDomains) ?? "com"
    return "https://\(host).\(tld)"
  }

  static func date<S: FakeSource>(in range: ClosedRange<Date>, using source: inout S) -> Date {
    let interval = source.double(
      in: range.lowerBound.timeIntervalSince1970...range.upperBound.timeIntervalSince1970
    )
    return Date(timeIntervalSince1970: interval)
  }
}
