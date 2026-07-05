/// # Authentication
///
/// Ported from platform-go's `authentication` package — but only the **client-relevant** slice, in
/// keeping with the iOS-only scope of this port (see `PORTING.md`). Concretely, this module carries
/// over the two pieces an iOS client actually runs locally:
///
/// * **TOTP** (`authentication/totp`) — RFC 6238 second-factor code generation and verification, the
///   thing an authenticator-app / 2FA-entry flow needs. See ``TOTP``. HMAC-SHA1/256/512 come from
///   CryptoKit, so codes match the Go side (`github.com/pquerna/otp`) byte-for-byte for the same
///   secret + time.
/// * **JWT claims + parse/verify** (`authentication/tokens` + `authentication/tokens/jwt`) — decoding a
///   compact JWS, verifying its signature, and validating the registered claims (`exp`/`nbf`/`iss`/
///   `aud`), plus typed access to standard and application-specific claims. See ``JWTParser`` and
///   ``JWTClaims``.
///
/// ## What is intentionally NOT ported
///
/// * **`authentication/argon2` — deferred (server-side).** Argon2id password hashing runs at *login*
///   on the server; an iOS client never verifies a stored password hash. It also has **no CryptoKit
///   analogue** — a faithful port means adding a heavy `swift-argon2`/libsodium C dependency, which we
///   decline (exactly as `PORTING.md` defers `salsa20`). Wire this up only if a flow genuinely needs
///   on-device Argon2.
/// * **`authentication.Authenticator` (authenticator.go) — dropped (server-side).** It is the password
///   hash/verify orchestration built on top of Argon2; the same server-side reasoning applies. Its one
///   design note that *does* travel — second-factor verification is decoupled from password
///   verification — is honored here: ``TOTP`` stands alone, coupled to nothing.
/// * **JWT *issuance* / signing (`signer.IssueToken`) — dropped (server-side).** Minting and signing
///   tokens is the identity provider's job and requires the server's private signing key; a client only
///   ever *consumes* tokens. The claim model and the parse/verify path a client needs are ported; the
///   HS256 `SignedString` issuance path is not. (Reserved-claim-key enforcement, `ErrReservedClaim`,
///   was an issuance-time guard and is likewise out of scope.)
///
/// ## Decoupled from Observability — by design
///
/// The Go verifier and signer wrap each call in an `observability.Observer` span. This port follows the
/// same precedent `Cryptography` set: a security primitive should not drag the observability graph into
/// a client, nor risk logging secret/token material. Failures surface as typed thrown errors
/// (``TOTPError``, ``JWTError``) that the caller traces at its own layer. As a result this module has
/// **no SPM dependencies** — only the system frameworks CryptoKit, Security, and Foundation.
public enum Authentication {}
