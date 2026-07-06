/// # Secrets
///
/// Ported from platform-go's `secrets` package (`secrets.go` + `noop/`, `env/`, `config/`) — the
/// client-relevant slice, per this port's iOS-only scope (see `PORTING.md`).
///
/// What travels over intact:
///   * ``SecretSource`` — the provider-seam protocol (``SecretSource/getSecret(name:)``,
///     ``SecretSource/close()``), ported from Go's `secrets.SecretSource` interface.
///   * ``SecretsError/notFound(_:)`` — the not-found/empty distinction Go's package-level
///     `secrets.ErrSecretNotFound` sentinel exists to preserve: a *missing* secret throws, while a
///     secret that legitimately stores an empty value returns `""` with no error. See that case's doc
///     for exactly how each conformer draws that line.
///   * ``NoopSecretSource`` and ``SecretSourceMock`` — the no-op and test-double conformers, ported
///     from `secrets/noop`.
///   * ``EnvironmentSecretSource`` — the direct analogue of `secrets/env`: reads `ProcessInfo`
///     environment variables (falling back to the bundle's `Info.plist`), for debug/simulator builds
///     where injecting a value at launch/build time is more convenient than seeding the Keychain.
///
/// What's new (no Go source, since Go's server processes have no Keychain):
///   * ``KeychainSecretSource`` — the **live**, native default. Backed by the `Security` framework's
///     generic-password items (`SecItemCopyMatching`), which is the closest native analogue to a
///     durable, access-controlled secret store on iOS/macOS.
///   * ``SecretsConfig`` — a lenient `Codable` provider-selection config, the analogue of Go's
///     `secretscfg.Config`. It keeps the `"gcp"`/`"ssm"`/`"kubectl"` provider strings *recognized* (so a
///     Go-authored payload still decodes), but selecting one throws
///     ``SecretsError/unsupportedProvider(_:)`` rather than reaching for a cloud SDK — see that type's
///     doc for what was dropped and why.
public enum Secrets {}
