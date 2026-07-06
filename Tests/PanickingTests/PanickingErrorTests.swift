import Testing

@testable import Panicking

@Suite("PanickingError equality")
struct PanickingErrorTests {
  @Test("same case with the same message is equal")
  func sameCaseSameMessage() {
    #expect(
      PanickingError.crashRequested(message: "x") == PanickingError.crashRequested(message: "x"))
  }

  @Test("same case with a different message is unequal")
  func sameCaseDifferentMessage() {
    #expect(
      PanickingError.crashRequested(message: "x") != PanickingError.crashRequested(message: "y"))
  }

  @Test("different cases are unequal even with the same message")
  func differentCases() {
    #expect(
      PanickingError.crashRequested(message: "x") != PanickingError.assertionFailed(message: "x"))
    #expect(
      PanickingError.assertionFailed(message: "x")
        != PanickingError.preconditionFailed(message: "x"))
  }
}
