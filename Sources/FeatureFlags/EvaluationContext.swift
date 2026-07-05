/// Carries targeting information for a single flag evaluation, ported from platform-go's
/// `featureflags.EvaluationContext` (`feature_flag_manager.go`).
///
/// ``targetingKey`` is the primary subject identifier, typically a user ID, but it can be any stable
/// string a provider's targeting rules can match against. ``attributes`` carries arbitrary additional
/// signals (tenant, plan tier, country, beta cohort, region, etc.) that provider rules can target on.
///
/// This type is intentionally repo-owned rather than aliasing an OpenFeature SDK type, matching the Go
/// origin's own rationale: it keeps a vendor SDK import out of caller code, lets ``NoopFeatureFlagManager``
/// and ``FeatureFlagManagerMock`` satisfy ``FeatureFlagManager`` without depending on one, and leaves room
/// for a real provider to convert to its own representation internally (were one ever wired up on this
/// platform; see ``FeatureFlagsConfig``).
public struct EvaluationContext: Sendable, Equatable {
  /// The primary subject identifier for targeting rules to match against.
  public var targetingKey: String
  /// Additional signals a provider's targeting rules can use (tenant, plan tier, region, etc.). Go's
  /// `map[string]any` becomes `[String: FlagValue]`: `Any` is not `Sendable`, and `FlagValue` is this
  /// port's `Sendable` stand-in for arbitrary JSON (see ``FlagValue``).
  public var attributes: [String: FlagValue]

  public init(targetingKey: String, attributes: [String: FlagValue] = [:]) {
    self.targetingKey = targetingKey
    self.attributes = attributes
  }
}
