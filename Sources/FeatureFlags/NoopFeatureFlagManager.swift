/// A ``FeatureFlagManager`` that always returns the supplied default value (or a falsy value for the
/// boolean variant), ported from platform-go's `featureflags/noop` subpackage.
///
/// Go isolates the no-op in its own package to dodge an import cycle with the interface; Swift has no such
/// pressure, so it folds into the `FeatureFlags` module as a plain, stateless `struct`. This is
/// ``FeatureFlagsConfig``'s fallback: an empty or unrecognized ``FeatureFlagsConfig/provider`` resolves
/// here, matching Go's `ProvideFeatureFlagManager` default case.
public struct NoopFeatureFlagManager: FeatureFlagManager {
  public init() {}

  public func canUseFeature(_ feature: String, context: EvaluationContext) async throws -> Bool {
    false
  }

  public func stringValue(
    for feature: String, default defaultValue: String, context: EvaluationContext
  ) async throws -> String {
    defaultValue
  }

  public func int64Value(
    for feature: String, default defaultValue: Int64, context: EvaluationContext
  ) async throws -> Int64 {
    defaultValue
  }

  public func float64Value(
    for feature: String, default defaultValue: Double, context: EvaluationContext
  ) async throws -> Double {
    defaultValue
  }

  public func objectValue(
    for feature: String, default defaultValue: FlagValue, context: EvaluationContext
  ) async throws -> FlagValue {
    defaultValue
  }

  public func close() async throws {}
}
