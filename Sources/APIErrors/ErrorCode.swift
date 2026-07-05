/// Application-level error codes returned in the `error.code` field of an API response, ported from
/// platform-go's `errors/http.ErrorCode` (`error_codes.go`). These are *not* HTTP status codes — they
/// are stable string identifiers (`E100`–`E112`) the client can branch on.
///
/// Unknown raw values decode to ``nothingSpecific`` (Go's catch-all) rather than throwing, so a server
/// that introduces a new code never breaks decoding of an otherwise-valid response.
public enum ErrorCode: String, Codable, Sendable, CaseIterable {
  /// Catch-all when no more specific code applies.
  case nothingSpecific = "E100"
  case fetchingSessionContextData = "E101"
  case decodingRequestInput = "E102"
  case validatingRequestInput = "E103"
  case dataNotFound = "E104"
  case talkingToDatabase = "E105"
  case misbehavingDependency = "E106"
  case talkingToSearchProvider = "E107"
  case secretGeneration = "E108"
  case userIsBanned = "E109"
  case userIsNotAuthorized = "E110"
  case encryptionIssue = "E111"
  case circuitBroken = "E112"

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = ErrorCode(rawValue: raw) ?? .nothingSpecific
  }
}

extension ErrorCode {
  /// The caller is not allowed to perform the action (banned or unauthorized) — typically surface a
  /// sign-in / permission prompt rather than a generic error.
  public var isAuthorizationError: Bool {
    self == .userIsNotAuthorized || self == .userIsBanned
  }

  /// The requested resource does not exist.
  public var isNotFound: Bool { self == .dataNotFound }

  /// The request itself was bad (malformed or failed validation) — retrying unchanged won't help.
  public var isValidationError: Bool {
    self == .validatingRequestInput || self == .decodingRequestInput
  }

  /// A transient backend/dependency failure where retrying (ideally with backoff) is reasonable.
  public var isRetryable: Bool {
    switch self {
    case .circuitBroken, .misbehavingDependency, .talkingToDatabase, .talkingToSearchProvider:
      return true
    default:
      return false
    }
  }
}
