/// Small, embedded string corpora backing ``Fake`` and ``FakeGenerator``.
///
/// These are deliberately short (a few dozen entries each) — the goal is plausible-looking test
/// and preview data, not exhaustive coverage. Kept as a dedicated file so the corpora are easy to
/// extend without touching the generation logic in `FakeEngine.swift`.
enum FakeCorpus {
  static let firstNames: [String] = [
    "Ava", "Liam", "Noah", "Emma", "Oliver", "Sophia", "Elijah", "Isabella", "James", "Mia",
    "Benjamin", "Charlotte", "Lucas", "Amelia", "Henry", "Harper", "Alexander", "Evelyn", "Mason",
    "Abigail", "Ethan", "Emily", "Daniel", "Elizabeth", "Jacob", "Sofia", "Logan", "Avery",
    "Jackson", "Ella", "Sebastian", "Scarlett", "Jack", "Grace", "Owen", "Chloe", "Samuel",
    "Victoria", "Matthew", "Riley", "Joseph", "Aria", "Levi", "Lily", "Mateo", "Aurora", "David",
    "Zoey", "John", "Nora",
  ]

  static let lastNames: [String] = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez",
    "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor",
    "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez",
    "Clark", "Ramirez", "Lewis", "Robinson", "Walker", "Young", "Allen", "King", "Wright",
    "Scott", "Torres", "Nguyen", "Hill", "Flores", "Green", "Adams", "Nelson", "Baker", "Hall",
    "Rivera", "Campbell", "Mitchell", "Carter", "Roberts",
  ]

  static let loremWords: [String] = [
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
    "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim",
    "ad", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi",
    "aliquip", "ex", "ea", "commodo", "consequat", "duis", "aute", "irure", "in", "reprehenderit",
    "voluptate", "velit", "esse", "cillum", "eu", "fugiat", "nulla", "pariatur", "excepteur",
    "sint", "occaecat", "cupidatat", "non", "proident", "sunt", "culpa", "qui", "officia",
    "deserunt", "mollit", "anim", "id", "est", "laborum",
  ]

  static let emailDomains: [String] = [
    "example.com", "example.org", "example.net", "test.dev", "fixture.io", "mail.test",
    "sample.co", "preview.app",
  ]

  static let topLevelDomains: [String] = [
    "com", "org", "net", "io", "dev", "app", "co",
  ]
}
