import Testing

@testable import Panicking

/// `crash`/`crashf` really do trap the process, so — mirroring the brief's guidance that the live
/// conformer can't be exercised directly — these tests only cover the paths that don't crash: passing
/// `assert`/`precondition` checks (mirrors Go's `TestNewProductionPanicker` construction smoke test) and
/// existential conformance.
@Suite("StandardPanicker")
struct StandardPanickerTests {
  @Test("conforms to Panicker and can be constructed behind the existential")
  func conformance() {
    let panicker: any Panicker = StandardPanicker()
    #expect(panicker is StandardPanicker)
  }

  @Test("a true condition does not trap for assert")
  func assertPasses() throws {
    try StandardPanicker().assert(true, "should not fire")
  }

  @Test("a true condition does not trap for precondition")
  func preconditionPasses() throws {
    try StandardPanicker().precondition(true, "should not fire")
  }

  @Test("assert's message default overload does not trap on a true condition")
  func assertDefaultMessage() throws {
    try StandardPanicker().assert(1 == 1)
  }

  @Test("precondition's message default overload does not trap on a true condition")
  func preconditionDefaultMessage() throws {
    try StandardPanicker().precondition(1 == 1)
  }
}
