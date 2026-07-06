import Foundation
import Observability
import Security

/// A **live** ``SecretSource`` backed by the platform Keychain, via the `Security` framework's
/// generic-password items (`SecItemCopyMatching`/`kSecClassGenericPassword`).
///
/// Go's `secrets` package has no analogue for this type: its backends (`env`, `gcp`, `ssm`, `kubectl`)
/// all target environments with no Keychain. This is the closest native equivalent to those backends'
/// role — a durable, OS-managed, access-controlled store for values that shouldn't live in
/// `UserDefaults` or the app bundle — so it stands in as this port's primary/default conformer (see
/// ``SecretsConfig``). Every lookup and the shutdown hook are threaded through an injected
/// ``Observability/Observer``, the same instrumentation shape Go's `env.envSecretSource.GetSecret`
/// uses: a named operation records the secret's *lookup key* (never its value) on the span/logger,
/// increments a `_lookups` counter, and records a `_latency_ms` histogram — matching Go's
/// `lookupCounter`/`latencyHist` metric names (with a `keychain_secret_source` prefix in place of Go's
/// `env_secret_source`).
///
/// **The not-found/empty distinction** (see ``SecretSource``): `SecItemCopyMatching` returning
/// `errSecItemNotFound` throws ``SecretsError/notFound(_:)``. A Keychain item that exists but stores
/// zero-length data (a legitimately empty secret) decodes to `""` and returns normally, with no throw —
/// exactly mirroring Go's env backend distinguishing an unset environment variable (error) from one set
/// to `""` (no error).
public struct KeychainSecretSource: SecretSource {
  /// Observability/metric name, matching the `env_secret_source`-style naming Go's backends use.
  public static let o11yName = "keychain_secret_source"

  /// The Keychain `kSecAttrService` value every item is scoped under. Items written by other
  /// components (or other apps, absent a shared access group) are invisible to this source.
  private let service: String
  /// Optional `kSecAttrAccessGroup`, for sharing secrets across an app group's targets/extensions.
  private let accessGroup: String?
  private let observer: any Observer
  private let metrics: any MetricsProvider

  /// Primary initializer — inject an observer and metrics provider directly (the test seam).
  public init(
    service: String,
    accessGroup: String? = nil,
    observer: any Observer = LiveObserver(
      name: KeychainSecretSource.o11yName, logger: NoopLogger(), tracer: NoopTracer()),
    metrics: any MetricsProvider = NoopMetricsProvider()
  ) {
    self.service = service
    self.accessGroup = accessGroup
    self.observer = observer
    self.metrics = metrics
  }

  /// Convenience initializer — the analogue of Go's `env.NewEnvSecretSource(logger, tracerProvider,
  /// metricsProvider)`, built from bootstrapped ``Pillars`` instead of three separate parameters.
  public init(service: String, accessGroup: String? = nil, pillars: Pillars) {
    self.init(
      service: service,
      accessGroup: accessGroup,
      observer: makeObserver(KeychainSecretSource.o11yName, pillars),
      metrics: pillars.metrics)
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

      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: name,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      if let accessGroup {
        query[kSecAttrAccessGroup as String] = accessGroup
      }

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)

      switch status {
      case errSecSuccess:
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
          let error = SecretsError.malformedSecretData(name: name)
          op.acknowledge(error, "keychain item is not valid UTF-8")
          throw error
        }
        return value
      case errSecItemNotFound:
        // Thrown *raw* (not wrapped via `op.error`), matching `LLMHTTP`'s convention of letting a
        // typed, expected failure propagate as itself while still recording it — a caller pattern-
        // matching `catch SecretsError.notFound` must see this case, not an opaque wrapper.
        let error = SecretsError.notFound(name)
        op.acknowledge(error, "keychain item not found")
        throw error
      default:
        let error = SecretsError.keychainFailure(name: name, status: status)
        op.acknowledge(error, "keychain lookup failed")
        throw error
      }
    }
  }

  public func close() async {
    observer.logger.debug("closing keychain secret source")
  }
}
