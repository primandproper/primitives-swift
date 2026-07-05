import Foundation
import Testing

@testable import APIErrors

@Suite("ErrorCode")
struct ErrorCodeTests {
  @Test("raw values match the Go E1xx codes")
  func rawValues() {
    #expect(ErrorCode.nothingSpecific.rawValue == "E100")
    #expect(ErrorCode.dataNotFound.rawValue == "E104")
    #expect(ErrorCode.circuitBroken.rawValue == "E112")
    #expect(ErrorCode.allCases.count == 13)
  }

  @Test("an unknown code decodes to nothingSpecific instead of throwing")
  func unknownDecodesToCatchAll() throws {
    let decoded = try JSONDecoder().decode(ErrorCode.self, from: Data(#""E999""#.utf8))
    #expect(decoded == .nothingSpecific)
  }

  @Test("a known code round-trips")
  func knownRoundTrip() throws {
    let decoded = try JSONDecoder().decode(ErrorCode.self, from: Data(#""E104""#.utf8))
    #expect(decoded == .dataNotFound)
    let reencoded = try JSONEncoder().encode(ErrorCode.userIsBanned)
    #expect(String(decoding: reencoded, as: UTF8.self) == #""E109""#)
  }

  @Test("classification helpers map codes to categories")
  func classification() {
    #expect(ErrorCode.userIsNotAuthorized.isAuthorizationError)
    #expect(ErrorCode.userIsBanned.isAuthorizationError)
    #expect(!ErrorCode.dataNotFound.isAuthorizationError)

    #expect(ErrorCode.dataNotFound.isNotFound)

    #expect(ErrorCode.validatingRequestInput.isValidationError)
    #expect(ErrorCode.decodingRequestInput.isValidationError)

    #expect(ErrorCode.circuitBroken.isRetryable)
    #expect(ErrorCode.talkingToDatabase.isRetryable)
    #expect(!ErrorCode.validatingRequestInput.isRetryable)
    #expect(!ErrorCode.encryptionIssue.isRetryable)
  }
}

@Suite("APIError")
struct APIErrorTests {
  @Test("description matches Go's \"CODE: message\" rendering")
  func description() {
    let err = APIError(message: "data not found", code: .dataNotFound)
    #expect(err.description == "E104: data not found")
  }

  @Test("is throwable as a Swift Error")
  func throwable() {
    let err = APIError(message: "nope", code: .userIsNotAuthorized)
    #expect(throws: APIError.self) { throw err }
  }
}

@Suite("APIResponse")
struct APIResponseTests {
  @Test("decodes the confirmed Go error-response wire shape")
  func decodeErrorResponse() throws {
    let json = Data(
      #"{"error":{"message":"data not found","code":"E104"},"details":{"currentAccountID":"","traceID":"t-1"}}"#
        .utf8)
    let response = try JSONDecoder().decode(ErrorResponse.self, from: json)

    #expect(response.error?.code == .dataNotFound)
    #expect(response.error?.message == "data not found")
    #expect(response.details.traceID == "t-1")
    #expect(response.data == nil)
  }

  @Test("get() throws the embedded error")
  func getThrowsError() {
    let response = APIResponse<String>(error: APIError(message: "banned", code: .userIsBanned))
    #expect(throws: APIError.self) { _ = try response.get() }
  }

  @Test("get() returns the payload on success")
  func getReturnsData() throws {
    let response = APIResponse<String>(data: "payload")
    #expect(try response.get() == "payload")
  }

  @Test("get() throws nothingSpecific when neither data nor error is present")
  func getThrowsOnEmpty() {
    let response = APIResponse<String>()
    #expect {
      try response.get()
    } throws: { error in
      (error as? APIError)?.code == .nothingSpecific
    }
  }

  @Test("decodes a success payload with nested pagination")
  func decodeSuccessWithPagination() throws {
    let json = Data(
      #"{"data":"ok","pagination":{"appliedQueryFilter":null,"cursor":"c2","previousCursor":"","filteredCount":1,"totalCount":1,"maxResponseSize":50},"details":{"currentAccountID":"acct","traceID":""}}"#
        .utf8)
    let response = try JSONDecoder().decode(APIResponse<String>.self, from: json)
    #expect(response.data == "ok")
    #expect(response.pagination?.cursor == "c2")
    #expect(response.details.currentAccountID == "acct")
  }
}
