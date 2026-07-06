import Foundation
import Observability

/// A ``SecretSource`` backed by process environment variables and, as a fallback, the app bundle's
/// `Info.plist`, ported from platform-go's `secrets/env` package (`env/env.go`).
///
/// Go's `envSecretSource.GetSecret` reads `os.LookupEnv` only. This port adds the `Info.plist` fallback
/// because environment variables are awkward to seed on iOS: setting one for a simulator run means
/// editing the scheme's "Arguments" tab, while `Info.plist` (or an `.xcconfig`-injected build setting)
/// is the conventional way debug/simulator builds carry a placeholder API key or test credential
/// without touching the Keychain. Intended for debug/simulator builds only — see ``KeychainSecretSource``
/// for the live/production default.
///
/// **The not-found/empty distinction** (see ``SecretSource``): a name absent from *both* the
/// environment and `Info.plist` throws ``SecretsError/notFound(_:)``, mirroring Go's `os.LookupEnv`
/// `ok == false` case exactly. A name present with an empty string value returns `""` with no throw,
/// mirroring Go's set-but-empty case.
public struct EnvironmentSecretSource: SecretSource {
  /// Observability/metric name, matching Go's `const name = "env_secret_source"` (prefixed
  /// `environment_` rather than `env_` to read unambiguously alongside ``KeychainSecretSource``'s name).
  public static let o11yName = "environment_secret_source"

  private let environment: [String: String]
  private let infoDictionary: [String: String]
  private let observer: any Observer
  private let metrics: any MetricsProvider

  /// Primary initializer — inject the environment/`Info.plist` maps and an observer/metrics provider
  /// directly (the test seam).
  ///
  /// `infoDictionary` takes `[String: Any]` (matching `Bundle.infoDictionary`'s own type) but only its
  /// `String`-valued entries are retained — a secret is always a string, and dropping the rest keeps
  /// this Keychain-adjacent type's storage `Sendable` without an unchecked escape hatch.
  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    observer: any Observer = LiveObserver(
      name: EnvironmentSecretSource.o11yName, logger: NoopLogger(), tracer: NoopTracer()),
    metrics: any MetricsProvider = NoopMetricsProvider()
  ) {
    self.environment = environment
    self.infoDictionary = infoDictionary.compactMapValues { $0 as? String }
    self.observer = observer
    self.metrics = metrics
  }

  /// Convenience initializer — the analogue of Go's `env.NewEnvSecretSource(logger, tracerProvider,
  /// metricsProvider)`.
  public init(pillars: Pillars) {
    self.init(
      observer: makeObserver(EnvironmentSecretSource.o11yName, pillars), metrics: pillars.metrics)
  }

  public func getSecret(name: String) async throws -> String {
    try await observer.operation(Self.o11yName) { op in
      // NOTE: only the secret's lookup key is observed, never its value — matching Go's identical
      // comment in `env.envSecretSource.GetSecret`.
      op.set("secret_key", name)

      let start = DispatchTime.now()
      defer {
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
        metrics.histogram("\(Self.o11yName)_latency_ms").record(Double(elapsedNanos) / 1_000_000)
      }
      metrics.counter("\(Self.o11yName)_lookups").increment()

      if let value = environment[name] {
        return value
      }
      if let value = infoDictionary[name] {
        return value
      }
      // Thrown *raw* (not wrapped via `op.error`), matching `LLMHTTP`'s convention of letting a typed,
      // expected failure propagate as itself while still recording it — a caller pattern-matching
      // `catch SecretsError.notFound` must see this case, not an opaque wrapper.
      let error = SecretsError.notFound(name)
      op.acknowledge(error, "secret not set in environment or Info.plist")
      throw error
    }
  }

  public func close() async {
    observer.logger.debug("closing environment secret source")
  }
}
