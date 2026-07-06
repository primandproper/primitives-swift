/// Provides access to secrets, ported from platform-go's `secrets.SecretSource` interface
/// (`secrets/secrets.go`):
/// ```go
/// type SecretSource interface {
///   GetSecret(ctx context.Context, name string) (string, error)
///   Close() error
/// }
/// ```
/// `context.Context` is dropped (per this port's settled conventions — see `PORTING.md`); `getSecret`
/// is `async throws` instead so a real backend can suspend (a Keychain call, a network round-trip for a
/// future vendor adapter) and fail without Go's explicit `ctx`/`error` plumbing. `close()` is `async`
/// for the same reason, though every conformer in this port completes it synchronously today.
///
/// **The not-found/empty distinction.** A missing secret and a secret whose value is legitimately the
/// empty string must stay distinguishable, exactly as in Go: a caller that gets back `""` needs to know
/// whether that means "no such secret" or "this secret is set to nothing." Go draws the line with a
/// sentinel error, `secrets.ErrSecretNotFound`, that every backend returns for the "missing" case and
/// never for the "empty" case (see `env.envSecretSource.GetSecret`, which errors for an unset
/// environment variable but returns `""` with a `nil` error for one that's set-but-empty). This port
/// preserves that exact split with ``SecretsError/notFound(_:)``: every conformer here throws it when
/// the secret does not exist, and returns `""` un-thrown when the secret exists and is empty.
public protocol SecretSource: Sendable {
  /// Looks up the secret stored under `name`.
  ///
  /// - Returns: The secret's value. An empty string is a valid, legitimate value — it means the secret
  ///   is set to nothing, not that it's missing.
  /// - Throws: ``SecretsError/notFound(_:)`` when no secret exists under `name`. Mirrors Go's
  ///   `GetSecret` returning `("", secrets.ErrSecretNotFound)` for the same case.
  func getSecret(name: String) async throws -> String

  /// Releases any underlying resources. Mirrors Go's `Close() error`; this port's conformers have
  /// nothing that can fail to release, so it does not throw.
  func close() async
}
