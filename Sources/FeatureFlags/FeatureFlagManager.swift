/// Evaluates feature flags, ported from platform-go's `featureflags.FeatureFlagManager` interface
/// (`feature_flag_manager.go`).
///
/// Go's interface is five typed evaluators plus `Close() error`, each threading `context.Context` for
/// cancellation/tracing and returning `(value, error)` where `value` is *already* a safe fallback: on
/// error, `CanUseFeature` returns `false` and every `Get*Value` returns the caller-supplied default. That
/// "fail open with the caller's own default" contract is deliberate (a flag-provider outage must never
/// crash or block a feature check), and it survives the port unchanged: a thrown error still leaves the
/// caller holding the exact default it passed in, so `catch { return defaultValue }` at the call site is
/// trivial and matches Go's behavior exactly.
///
/// `context.Context` threading becomes Swift structured concurrency (`async`), per this port's settled
/// convention; implementations that do no asynchronous work (``NoopFeatureFlagManager``) satisfy the
/// `async` requirements trivially.
public protocol FeatureFlagManager: Sendable {
  /// Evaluates a boolean flag. Ported from Go's `CanUseFeature`.
  /// - Throws: an implementation-defined error; the caller should treat a thrown error the same as `false`.
  func canUseFeature(_ feature: String, context: EvaluationContext) async throws -> Bool

  /// Evaluates a string-typed flag. Ported from Go's `GetStringValue`.
  /// - Throws: an implementation-defined error; the caller should fall back to `defaultValue`.
  func stringValue(for feature: String, default defaultValue: String, context: EvaluationContext)
    async throws -> String

  /// Evaluates an int64-typed flag. Ported from Go's `GetInt64Value`.
  /// - Throws: an implementation-defined error; the caller should fall back to `defaultValue`.
  func int64Value(for feature: String, default defaultValue: Int64, context: EvaluationContext)
    async throws -> Int64

  /// Evaluates a float64-typed flag. Ported from Go's `GetFloat64Value`.
  /// - Throws: an implementation-defined error; the caller should fall back to `defaultValue`.
  func float64Value(for feature: String, default defaultValue: Double, context: EvaluationContext)
    async throws -> Double

  /// Evaluates an object-typed (JSON) flag. Ported from Go's `GetObjectValue`; Go's `any` becomes
  /// ``FlagValue``, the `Sendable` JSON value this port uses in place of `Any`.
  /// - Throws: an implementation-defined error; the caller should fall back to `defaultValue`.
  func objectValue(for feature: String, default defaultValue: FlagValue, context: EvaluationContext)
    async throws -> FlagValue

  /// Releases any backend resources held by the manager. Ported from Go's `Close`.
  func close() async throws
}
