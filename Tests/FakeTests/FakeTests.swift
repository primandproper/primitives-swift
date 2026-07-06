import Foundation
import Identifiers
import Testing

@testable import Fake

@Suite("Fake static generators")
struct FakeStaticGeneratorTests {
  @Test("names are non-empty and full name combines first and last")
  func names() {
    #expect(!Fake.firstName().isEmpty)
    #expect(!Fake.lastName().isEmpty)
    let full = Fake.fullName()
    #expect(full.contains(" "))
    #expect(!full.isEmpty)
  }

  @Test("username is non-empty and lowercase-shaped")
  func username() {
    let name = Fake.username()
    #expect(!name.isEmpty)
    #expect(name == name.lowercased())
  }

  @Test("email contains exactly one @ and a reserved-for-testing domain")
  func email() {
    let address = Fake.email()
    let parts = address.split(separator: "@")
    #expect(parts.count == 2)
    #expect(FakeCorpus.emailDomains.contains(String(parts[1])))
  }

  @Test("lorem word is drawn from the embedded corpus")
  func word() {
    #expect(FakeCorpus.loremWords.contains(Fake.word()))
  }

  @Test("sentence is capitalized, period-terminated, and honors an explicit word count")
  func sentence() {
    let sentence = Fake.sentence(wordCount: 5)
    #expect(sentence.hasSuffix("."))
    #expect(sentence.split(separator: " ").count == 5)
    let first = sentence.first.map(String.init) ?? ""
    #expect(first == first.uppercased())
  }

  @Test("default sentence and paragraph are non-empty")
  func defaultLorem() {
    #expect(!Fake.sentence().isEmpty)
    #expect(!Fake.paragraph().isEmpty)
  }

  @Test("paragraph honors an explicit sentence count")
  func paragraph() {
    let text = Fake.paragraph(sentenceCount: 3)
    let sentenceCount = text.filter { $0 == "." }.count
    #expect(sentenceCount == 3)
  }

  @Test("phone number matches the expected shape")
  func phoneNumber() {
    let phone = Fake.phoneNumber()
    let pattern = #/^\(\d{3}\) \d{3}-\d{4}$/#
    #expect(phone.wholeMatch(of: pattern) != nil)
  }

  @Test("url is well-formed https")
  func url() {
    let url = Fake.url()
    #expect(url.hasPrefix("https://"))
    #expect(URL(string: url) != nil)
  }

  @Test("uuid round-trips through Foundation.UUID")
  func uuid() {
    #expect(UUID(uuidString: Fake.uuid()) != nil)
  }

  @Test("xid is a valid Identifiers xid")
  func xid() {
    #expect(Identifier.isValid(Fake.xid()))
  }

  @Test("bool returns without trapping")
  func bool() {
    _ = Fake.bool()
  }

  @Test("int respects its range")
  func intInRange() {
    for _ in 0..<50 {
      let value = Fake.int(in: 10...20)
      #expect(value >= 10 && value <= 20)
    }
  }

  @Test("double respects its range")
  func doubleInRange() {
    for _ in 0..<50 {
      let value = Fake.double(in: 1.0...2.0)
      #expect(value >= 1.0 && value <= 2.0)
    }
  }

  @Test("date respects its range")
  func dateInRange() {
    let start = Date(timeIntervalSince1970: 0)
    let end = Date(timeIntervalSince1970: 1000)
    for _ in 0..<20 {
      let value = Fake.date(in: start...end)
      #expect(value >= start && value <= end)
    }
  }

  @Test("pick returns an element from the array, and nil for empty input")
  func pick() {
    let options = [1, 2, 3]
    #expect(Fake.pick(from: options).map(options.contains) == true)
    let empty: [Int] = []
    #expect(Fake.pick(from: empty) == nil)
  }
}

@Suite("FakeGenerator seeded reproducibility")
struct FakeGeneratorSeededTests {
  @Test("same seed and call sequence produces identical output")
  func reproducible() {
    var a = FakeGenerator(seed: 42)
    var b = FakeGenerator(seed: 42)

    #expect(a.fullName() == b.fullName())
    #expect(a.email() == b.email())
    #expect(a.username() == b.username())
    #expect(a.sentence() == b.sentence())
    #expect(a.paragraph() == b.paragraph())
    #expect(a.phoneNumber() == b.phoneNumber())
    #expect(a.url() == b.url())
    #expect(a.bool() == b.bool())
    #expect(a.int(in: 0...1000) == b.int(in: 0...1000))
    #expect(a.double(in: 0...1000) == b.double(in: 0...1000))
    #expect(a.pick(from: [1, 2, 3, 4, 5]) == b.pick(from: [1, 2, 3, 4, 5]))
  }

  @Test("different seeds are very likely to diverge")
  func differentSeedsDiverge() {
    var a = FakeGenerator(seed: 1)
    var b = FakeGenerator(seed: 2)

    // Compare a handful of draws so a single coincidental corpus collision cannot flake the test.
    let sequenceA = (0..<5).map { _ in a.fullName() }
    let sequenceB = (0..<5).map { _ in b.fullName() }
    #expect(sequenceA != sequenceB)
  }

  @Test("seeded values are non-empty and in range")
  func seededValuesAreValid() {
    var generator = FakeGenerator(seed: 7)
    #expect(!generator.firstName().isEmpty)
    #expect(!generator.lastName().isEmpty)
    #expect(!generator.word().isEmpty)

    let value = generator.int(in: 5...9)
    #expect(value >= 5 && value <= 9)

    let doubleValue = generator.double(in: 0...1)
    #expect(doubleValue >= 0 && doubleValue <= 1)
  }

  @Test("seeded date respects its range")
  func seededDateInRange() {
    var generator = FakeGenerator(seed: 99)
    let start = Date(timeIntervalSince1970: 0)
    let end = Date(timeIntervalSince1970: 1000)
    let value = generator.date(in: start...end)
    #expect(value >= start && value <= end)
  }
}
