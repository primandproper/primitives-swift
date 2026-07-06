/// A no-op ``SecretSource``, ported from platform-go's `secrets/noop` package. Returns an empty string
/// for every lookup and never throws — used as the safe default when no secrets backend is configured.
///
/// Note this is the *legitimately empty* case, not the *not-found* case: mirroring Go's
/// `noop.secretSource.GetSecret` (`return "", nil`), this conformer never throws
/// ``SecretsError/notFound(_:)``. A caller relying on the noop source to signal "unconfigured" needs to
/// check elsewhere (e.g. ``SecretsConfig/provider``); this type alone can't distinguish the two.
public struct NoopSecretSource: SecretSource {
  public init() {}

  public func getSecret(name: String) async throws -> String {
    ""
  }

  public func close() async {}
}
