import CircuitBreaking
import Foundation

/// A **live**, native ``FeatureFlagManager`` backed by PostHog's remote flag-evaluation endpoint.
///
/// Go fronts PostHog with the OpenFeature SDK and the vendor `posthog-go` client
/// (`featureflags/posthog/feature_flag_manager.go`). Neither ships an iOS analogue worth vendoring, so
/// this port talks to the same HTTP surface those SDKs use, directly over `URLSession` + `Codable`, per
/// this repo's thin/native/no-dependency rule: each evaluation issues
///
///     POST {endpoint}/flags/?v=2
///     { "api_key": <projectAPIKey>, "distinct_id": <targetingKey>, "person_properties": <attributes> }
///
/// and reads `featureFlags` / `featureFlagPayloads` from the JSON response — the exact shape the Go
/// `posthog` package's own test server returns (`featureflags/posthog/feature_flag_manager_test.go`).
/// The `/flags/?v=2` path is PostHog's current name for the endpoint historically served at
/// `/decide/?v=3`; both return the same `{featureFlags, featureFlagPayloads}` body, and the Go test
/// harness routes on the `/flags/` prefix, so that is the path chosen here.
///
/// **Fail-open contract.** Every evaluator honors ``FeatureFlagManager``'s documented contract: on *any*
/// failure — the breaker being open, a transport error, a non-2xx status, a malformed body, or a
/// missing/mistyped flag — it returns the caller's supplied default (`false` for ``canUseFeature(_:context:)``)
/// rather than throwing. A flag-provider outage must never crash or block a feature check.
///
/// **Circuit breaker.** Each request is guarded by the injected ``CircuitBreaking/CircuitBreaker`` built
/// from ``PostHogConfig/circuitBreaker``: an open breaker short-circuits the call (still fail-open to the
/// default), and request outcomes are recorded so a failing PostHog can trip it — mirroring the Go
/// manager's `CanProceed`/`Succeeded`/`Failed` bookkeeping.
public struct PostHogFeatureFlagManager: FeatureFlagManager {
  /// PostHog US Cloud's ingestion host, used when ``PostHogConfig/endpoint`` is empty — the analogue of
  /// the `posthog-go` SDK's default endpoint.
  public static let defaultEndpoint = "https://us.i.posthog.com"

  private let session: URLSession
  private let projectAPIKey: String
  /// The resolved base host (no trailing slash), already defaulted away from empty.
  private let endpoint: String
  private let circuitBreaker: any CircuitBreaker

  /// Primary initializer — inject an already-built session and breaker (the test seam).
  public init(
    projectAPIKey: String,
    endpoint: String = "",
    session: URLSession,
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker()
  ) {
    self.projectAPIKey = projectAPIKey
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolved = trimmed.isEmpty ? Self.defaultEndpoint : trimmed
    // Normalize away a trailing slash so `\(endpoint)/flags/` never doubles up.
    self.endpoint = resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    self.session = session
    self.circuitBreaker = circuitBreaker
  }

  /// Convenience initializer — the analogue of Go's `posthog.NewFeatureFlagManager(...)`. Builds the
  /// guarding breaker from ``PostHogConfig/circuitBreaker`` and a default `URLSession` unless one is
  /// injected.
  public init(config: PostHogConfig, session: URLSession? = nil) {
    self.init(
      projectAPIKey: config.projectAPIKey,
      endpoint: config.endpoint,
      session: session ?? Self.makeSession(),
      circuitBreaker: config.circuitBreaker.provideCircuitBreaker())
  }

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }

  // MARK: - FeatureFlagManager

  public func canUseFeature(_ feature: String, context: EvaluationContext) async throws -> Bool {
    guard let flags = try? await fetchFlags(context: context) else { return false }
    switch flags.featureFlags[feature] {
    case .some(.bool(let enabled)):
      return enabled
    case .none, .some(.null):
      return false
    case .some:
      // A present, non-boolean value is a multivariate variant, i.e. the flag is enabled.
      return true
    }
  }

  public func stringValue(
    for feature: String, default defaultValue: String, context: EvaluationContext
  ) async throws -> String {
    guard let flags = try? await fetchFlags(context: context) else { return defaultValue }
    return flags.featureFlags[feature]?.stringValue ?? defaultValue
  }

  public func int64Value(
    for feature: String, default defaultValue: Int64, context: EvaluationContext
  ) async throws -> Int64 {
    guard let flags = try? await fetchFlags(context: context) else { return defaultValue }
    switch flags.featureFlags[feature] {
    case .some(.string(let raw)):
      // PostHog returns multivariate payloads as strings; parse to the requested type.
      return Int64(raw) ?? defaultValue
    case .some(.number(let value)):
      return Int64(exactly: value.rounded(.towardZero)) ?? defaultValue
    default:
      return defaultValue
    }
  }

  public func float64Value(
    for feature: String, default defaultValue: Double, context: EvaluationContext
  ) async throws -> Double {
    guard let flags = try? await fetchFlags(context: context) else { return defaultValue }
    switch flags.featureFlags[feature] {
    case .some(.string(let raw)):
      return Double(raw) ?? defaultValue
    case .some(.number(let value)):
      return value
    default:
      return defaultValue
    }
  }

  public func objectValue(
    for feature: String, default defaultValue: FlagValue, context: EvaluationContext
  ) async throws -> FlagValue {
    guard let flags = try? await fetchFlags(context: context) else { return defaultValue }
    // Prefer an explicit payload; PostHog delivers it (and multivariate object variants) as a
    // JSON-encoded string, so parse a string value into structured JSON before handing it back.
    if let payload = flags.featureFlagPayloads[feature], let parsed = Self.structured(payload) {
      return parsed
    }
    if let variant = flags.featureFlags[feature], let parsed = Self.structured(variant) {
      return parsed
    }
    return defaultValue
  }

  public func close() async throws {}

  // MARK: - Transport

  /// A single flag-evaluation response, tolerant of either map being absent (both default to empty).
  private struct DecideResponse: Decodable {
    var featureFlags: [String: FlagValue]
    var featureFlagPayloads: [String: FlagValue]

    private enum CodingKeys: String, CodingKey {
      case featureFlags
      case featureFlagPayloads
    }

    init(from decoder: any Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      featureFlags = try c.decodeIfPresent([String: FlagValue].self, forKey: .featureFlags) ?? [:]
      featureFlagPayloads =
        try c.decodeIfPresent([String: FlagValue].self, forKey: .featureFlagPayloads) ?? [:]
    }
  }

  private struct DecideRequest: Encodable {
    let apiKey: String
    let distinctId: String
    let personProperties: [String: FlagValue]

    enum CodingKeys: String, CodingKey {
      case apiKey = "api_key"
      case distinctId = "distinct_id"
      case personProperties = "person_properties"
    }
  }

  /// Interprets a ``FlagValue`` as structured JSON: an already-structured object/array/scalar is
  /// returned as-is, while a `.string` payload is re-parsed (PostHog encodes object payloads as JSON
  /// strings). Returns `nil` when a string doesn't parse.
  private static func structured(_ value: FlagValue) -> FlagValue? {
    if case .string(let raw) = value {
      guard let data = raw.data(using: .utf8),
        let parsed = try? JSONDecoder().decode(FlagValue.self, from: data)
      else { return nil }
      return parsed
    }
    return value
  }

  /// Issues one guarded decide call, returning the parsed response or throwing on breaker-open,
  /// transport, status, or decode failure (the evaluators translate any throw into the caller's default).
  private func fetchFlags(context: EvaluationContext) async throws -> DecideResponse {
    try await circuitBreaker.execute {
      guard let url = URL(string: "\(endpoint)/flags/?v=2") else {
        throw PostHogRequestError.invalidEndpoint(endpoint)
      }

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(
        DecideRequest(
          apiKey: projectAPIKey,
          distinctId: context.targetingKey,
          personProperties: context.attributes))

      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw PostHogRequestError.nonHTTPResponse
      }
      guard (200..<300).contains(http.statusCode) else {
        throw PostHogRequestError.unacceptableStatus(http.statusCode)
      }
      return try JSONDecoder().decode(DecideResponse.self, from: data)
    }
  }
}

/// Failures raised inside a decide call. All are swallowed by the fail-open evaluators; the type exists
/// so the breaker records a genuine failure (and so a future observability seam could classify them).
enum PostHogRequestError: Error, Equatable {
  case invalidEndpoint(String)
  case nonHTTPResponse
  case unacceptableStatus(Int)
}
