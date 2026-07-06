import Testing

@testable import Panicking

@Suite("NoopPanicker")
struct NoopPanickerTests {
  @Test("crash throws crashRequested instead of trapping")
  func crashThrows() {
    #expect(throws: PanickingError.crashRequested(message: "boom")) {
      try NoopPanicker().crash("boom")
    }
  }

  @Test("crashf formats the message and throws crashRequested instead of trapping")
  func crashfThrows() {
    #expect(throws: PanickingError.crashRequested(message: "boom 42")) {
      try NoopPanicker().crashf("boom %d", 42)
    }
  }

  @Test("assert never throws or traps, even on a false condition")
  func assertNeverThrows() throws {
    try NoopPanicker().assert(false, "would trap on a real panicker")
  }

  @Test("precondition never throws or traps, even on a false condition")
  func preconditionNeverThrows() throws {
    try NoopPanicker().precondition(false, "would trap on a real panicker")
  }

  @Test("assert's condition is never evaluated")
  func assertConditionNotEvaluated() throws {
    var evaluated = false
    try NoopPanicker().assert(
      {
        evaluated = true
        return false
      }(), "message")
    #expect(!evaluated)
  }
}
