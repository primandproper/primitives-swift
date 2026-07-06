/// A configurable ``FeatureFlagManager`` test double, the Swift analogue of the moq-generated
/// `FeatureFlagManagerMock` in platform-go's `featureflags/mock` package.
///
/// Go generates one `*Func` closure per method plus a `*Calls()` accessor that replays recorded
/// invocations, guarded by a `sync.RWMutex`. Swift's structured concurrency makes a class-based recorder
/// awkward under strict concurrency, since mutable state shared across `async` call sites needs
/// synchronization, so this is ported as an `actor`: every method runs on the actor's isolation, handler
/// closures are `@Sendable`, and each call's arguments are appended to a per-method array a test can
/// inspect afterward, mirroring Go's `mockedManager.CanUseFeatureCalls()` shape.
///
/// A handler left unset panics when its method is invoked, exactly like Go's generated mock ("mock out
/// the CanUseFeature method"), so a test only has to stub what it actually exercises.
///
/// The handler closures are `let`, injected once at ``init``: under Swift 6 actor isolation a
/// `public var` on an actor cannot be assigned from another isolation domain
/// (`mock.canUseFeatureHandler = …` would be a cross-actor mutation error), so configuration happens at
/// construction time — the shape the existing tests already use.
public actor FeatureFlagManagerMock: FeatureFlagManager {
  public struct CanUseFeatureCall: Sendable, Equatable {
    public let feature: String
    public let context: EvaluationContext
  }

  public struct StringValueCall: Sendable, Equatable {
    public let feature: String
    public let defaultValue: String
    public let context: EvaluationContext
  }

  public struct Int64ValueCall: Sendable, Equatable {
    public let feature: String
    public let defaultValue: Int64
    public let context: EvaluationContext
  }

  public struct Float64ValueCall: Sendable, Equatable {
    public let feature: String
    public let defaultValue: Double
    public let context: EvaluationContext
  }

  public struct ObjectValueCall: Sendable, Equatable {
    public let feature: String
    public let defaultValue: FlagValue
    public let context: EvaluationContext
  }

  private let canUseFeatureHandler: (@Sendable (String, EvaluationContext) async throws -> Bool)?
  private let stringValueHandler:
    (@Sendable (String, String, EvaluationContext) async throws -> String)?
  private let int64ValueHandler:
    (@Sendable (String, Int64, EvaluationContext) async throws -> Int64)?
  private let float64ValueHandler:
    (@Sendable (String, Double, EvaluationContext) async throws -> Double)?
  private let objectValueHandler:
    (@Sendable (String, FlagValue, EvaluationContext) async throws -> FlagValue)?
  private let closeHandler: (@Sendable () async throws -> Void)?

  public private(set) var canUseFeatureCalls: [CanUseFeatureCall] = []
  public private(set) var stringValueCalls: [StringValueCall] = []
  public private(set) var int64ValueCalls: [Int64ValueCall] = []
  public private(set) var float64ValueCalls: [Float64ValueCall] = []
  public private(set) var objectValueCalls: [ObjectValueCall] = []
  public private(set) var closeCallCount = 0

  public init(
    canUseFeature: (@Sendable (String, EvaluationContext) async throws -> Bool)? = nil,
    stringValue: (@Sendable (String, String, EvaluationContext) async throws -> String)? = nil,
    int64Value: (@Sendable (String, Int64, EvaluationContext) async throws -> Int64)? = nil,
    float64Value: (@Sendable (String, Double, EvaluationContext) async throws -> Double)? = nil,
    objectValue: (@Sendable (String, FlagValue, EvaluationContext) async throws -> FlagValue)? =
      nil,
    close: (@Sendable () async throws -> Void)? = nil
  ) {
    self.canUseFeatureHandler = canUseFeature
    self.stringValueHandler = stringValue
    self.int64ValueHandler = int64Value
    self.float64ValueHandler = float64Value
    self.objectValueHandler = objectValue
    self.closeHandler = close
  }

  public func canUseFeature(_ feature: String, context: EvaluationContext) async throws -> Bool {
    canUseFeatureCalls.append(CanUseFeatureCall(feature: feature, context: context))
    guard let handler = canUseFeatureHandler else {
      fatalError("FeatureFlagManagerMock.canUseFeatureHandler is nil but canUseFeature was called")
    }
    return try await handler(feature, context)
  }

  public func stringValue(
    for feature: String, default defaultValue: String, context: EvaluationContext
  ) async throws -> String {
    stringValueCalls.append(
      StringValueCall(feature: feature, defaultValue: defaultValue, context: context))
    guard let handler = stringValueHandler else {
      fatalError("FeatureFlagManagerMock.stringValueHandler is nil but stringValue was called")
    }
    return try await handler(feature, defaultValue, context)
  }

  public func int64Value(
    for feature: String, default defaultValue: Int64, context: EvaluationContext
  ) async throws -> Int64 {
    int64ValueCalls.append(
      Int64ValueCall(feature: feature, defaultValue: defaultValue, context: context))
    guard let handler = int64ValueHandler else {
      fatalError("FeatureFlagManagerMock.int64ValueHandler is nil but int64Value was called")
    }
    return try await handler(feature, defaultValue, context)
  }

  public func float64Value(
    for feature: String, default defaultValue: Double, context: EvaluationContext
  ) async throws -> Double {
    float64ValueCalls.append(
      Float64ValueCall(feature: feature, defaultValue: defaultValue, context: context))
    guard let handler = float64ValueHandler else {
      fatalError("FeatureFlagManagerMock.float64ValueHandler is nil but float64Value was called")
    }
    return try await handler(feature, defaultValue, context)
  }

  public func objectValue(
    for feature: String, default defaultValue: FlagValue, context: EvaluationContext
  ) async throws -> FlagValue {
    objectValueCalls.append(
      ObjectValueCall(feature: feature, defaultValue: defaultValue, context: context))
    guard let handler = objectValueHandler else {
      fatalError("FeatureFlagManagerMock.objectValueHandler is nil but objectValue was called")
    }
    return try await handler(feature, defaultValue, context)
  }

  public func close() async throws {
    closeCallCount += 1
    guard let handler = closeHandler else {
      fatalError("FeatureFlagManagerMock.closeHandler is nil but close was called")
    }
    try await handler()
  }
}
