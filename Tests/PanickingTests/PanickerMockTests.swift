import Testing

@testable import Panicking

@Suite("PanickerMock recording")
struct PanickerMockRecordingTests {
  @Test("crash records the call and throws by default")
  func crashRecordsAndThrows() {
    let mock = PanickerMock()
    #expect(throws: PanickingError.crashRequested(message: "boom")) {
      try mock.crash("boom")
    }
    #expect(mock.crashCalls == [PanickerMock.CrashCall(message: "boom")])
  }

  @Test("crashf formats the message, records it, and throws by default")
  func crashfRecordsAndThrows() {
    let mock = PanickerMock()
    #expect(throws: PanickingError.crashRequested(message: "boom 42")) {
      try mock.crashf("boom %d", 42)
    }
    #expect(mock.crashfCalls == [PanickerMock.CrashCall(message: "boom 42")])
  }

  @Test("assert with a false condition records the call and throws by default")
  func assertFalseRecordsAndThrows() {
    let mock = PanickerMock()
    #expect(throws: PanickingError.assertionFailed(message: "nope")) {
      try mock.assert(false, "nope")
    }
    #expect(mock.assertCalls == [PanickerMock.ConditionalCall(condition: false, message: "nope")])
  }

  @Test("assert with a true condition records the call but does not throw")
  func assertTrueRecordsWithoutThrowing() throws {
    let mock = PanickerMock()
    try mock.assert(true, "fine")
    #expect(mock.assertCalls == [PanickerMock.ConditionalCall(condition: true, message: "fine")])
  }

  @Test("precondition with a false condition records the call and throws by default")
  func preconditionFalseRecordsAndThrows() {
    let mock = PanickerMock()
    #expect(throws: PanickingError.preconditionFailed(message: "nope")) {
      try mock.precondition(false, "nope")
    }
    #expect(
      mock.preconditionCalls == [PanickerMock.ConditionalCall(condition: false, message: "nope")])
  }

  @Test("precondition with a true condition records the call but does not throw")
  func preconditionTrueRecordsWithoutThrowing() throws {
    let mock = PanickerMock()
    try mock.precondition(true, "fine")
    #expect(
      mock.preconditionCalls == [PanickerMock.ConditionalCall(condition: true, message: "fine")])
  }

  @Test("multiple calls accumulate in call order")
  func accumulatesCalls() {
    let mock = PanickerMock()
    _ = try? mock.assert(true, "first")
    _ = try? mock.assert(false, "second")
    #expect(
      mock.assertCalls == [
        PanickerMock.ConditionalCall(condition: true, message: "first"),
        PanickerMock.ConditionalCall(condition: false, message: "second"),
      ])
  }
}

@Suite("PanickerMock shouldThrow configuration")
struct PanickerMockConfigurationTests {
  @Test("setShouldThrow reconfigures the mock without exercising the real trap")
  func setShouldThrowMutatesState() {
    // Constructed with shouldThrow: false (which would make crash/crashf actually trap), then flipped
    // back to true before any call is made — this exercises the mutator without ever letting the mock
    // reach the real `fatalError` path, which would crash the test runner.
    let mock = PanickerMock(shouldThrow: false)
    mock.setShouldThrow(true)
    #expect(throws: PanickingError.crashRequested(message: "x")) {
      try mock.crash("x")
    }
  }

  @Test("init(shouldThrow:) defaults to true")
  func defaultsToThrowing() {
    let mock = PanickerMock()
    #expect(throws: PanickingError.crashRequested(message: "default")) {
      try mock.crash("default")
    }
  }
}
