# platform-swift TODO

Compiled 2026-07-05 from a six-agent review of the full package (all 24 modules, ~9.9k lines,
558 tests green at review time) against `platform-go` one directory up. Items are grouped into
**waves ordered by implementation priority and dependency** — later waves assume earlier ones.
Within a wave, items are independent unless a `Deps:` line says otherwise.

Conventions for agents working this list:
- Re-verify each finding against current code before fixing (line numbers drift).
- Every fix lands with a regression test. Cross-language claims get a Go-produced fixture.
- The port's settled rules: thin/native/no-SPM-dep (URLSession+Codable, CryptoKit, StoreKit);
  own protocol seams shaped so native/vendor SDK adapters can wrap later; Codable config with
  **lenient decoding to Go zero values**; every protocol-bearing module ships a Noop and a Mock.
- ID prefixes: OBS (Observability), NET (HTTPClient/Retry/CircuitBreaking/EventStream),
  CRY (Cryptography/Auth/Identifiers/Encoding/Compression), SVC (LLM/Analytics/FeatureFlags/
  Capitalism/Notifications), UTIL (small modules), REPO (hygiene), PORT (new modules).

---

## Wave 1 — Correctness bugs (fix first; all independent unless noted)

- [x] **NET-01 (P1)** `Sources/CircuitBreaking/StandardCircuitBreaker.swift` — A failed half-open
  trial does not re-trip the breaker under production config: after the default 30s `resetTimeout`
  the 10s rolling window has aged out, so one failed trial can't reach `shouldTrip`, `state` stays
  `.halfOpen`, and all traffic flows to the dead dependency. Fix: in `recordFailure()`, when
  `state(at: now) == .halfOpen`, unconditionally set `openedAt = now` and bump the tripped counter.
  Existing tests mask this because they use `resetTimeout < window` (see NET-22/23).
- [x] **NET-02 (P1)** `Sources/HTTPClient/HTTPClient.swift` — Cancellation counts as a breaker
  failure: `circuitBreaker?.failed()` runs before the `CancellationError`/`URLError.cancelled`
  check, so a burst of user cancellations can trip a healthy circuit. Move the cancellation
  early-return above `failed()`. (Subsumed by NET-10 if HTTPClient adopts `CircuitBreaking.execute`.)
- [x] **NET-03 (P1)** `Sources/HTTPClient/HTTPClient.swift` — Any `HTTPURLResponse` (including
  100% 500s) records breaker *success*, so the breaker can never trip on the most common failure
  mode. Classify at least 502/503/504 as failures, or inject a status-classification closure
  (that seam also serves NET-12/13).
- [x] **OBS-01 (P1)** `Sources/Observability/Operation.swift` — Lost-update race in
  `LiveOperation.set`/`setValues`/`logOnly`: logger read under one lock acquisition, enriched
  outside it, stored under a second — concurrent `op.set` calls from task-group children silently
  drop keys. Stringify the value first, then do the read-modify-write inside a single `withLock`.
- [x] **OBS-02 (P1)** `Sources/Observability/Metrics.swift` — `NoopMetricsProvider` is not a noop:
  it builds instruments bound to the process-wide `MetricsSystem` factory, so after any
  `MetricsSystem.bootstrap` a `.noop`-configured component emits real metrics. Construct with the
  explicit `handler: NOOPMetricsHandler.instance` inits. (README text at lines ~156/178 becomes
  accurate once fixed.)
- [x] **OBS-03 (P1, privacy)** `Sources/Observability/Logger.swift` — `OSLogLogger` interpolates
  rendered messages including all field values with `privacy: .public`, defeating unified logging's
  PII redaction — the README's own `op.logOnly("user.email", email)` example lands email in
  publicly readable device logs. Render dynamic field values `.private` (or make privacy
  configurable per-logger in `LoggingConfig`), keeping keys/name public.
- [x] **NET-04 (P1)** `Sources/EventStream/SSEEventStream.swift`, `WebSocketEventStream.swift` —
  Abandoned consumers leak the connection: no `continuation.onTermination`, so breaking out of
  `for try await` without `close()` leaves the pump/receive loop and `URLSessionTask` running
  forever. Set `onTermination` to cancel the network/pump tasks (hop to the actor via an
  unstructured Task).
- [x] **NET-05 (P1)** `Sources/EventStream/Event.swift` — `Event` Codable round-trips payloads
  through `RawJSON.number(Double)`, silently corrupting int64 > 2^53 (snowflake IDs) and
  high-precision decimals where Go's `json.RawMessage` preserves bytes. Preserve raw payload bytes
  (slice the original `Data` for the payload subtree) or at least a `Decimal`/string-preserving
  number representation.
- [x] **SVC-01 (P1)** `Sources/Capitalism/StoreKitPurchaseManager.swift` — Consumable purchases can
  be permanently lost: transactions are `finish()`ed before the entitlement is returned/yielded, so
  a crash between `finish()` and persisting the grant loses a paid consumable (finished
  transactions aren't re-delivered). Yield/return first and expose finishing to the caller (a
  `finish()` handle on the result, or an awaited delivery closure); at minimum document the window.
- [x] **SVC-02 (P1)** `Sources/Capitalism/StoreKitPurchaseManager.swift` — Typed errors are erased:
  `throw op.error(CapitalismError…)` wraps everything in `ObservabilityError` (with one double-wrap
  path via the `@unknown default` branch), so callers can never `catch CapitalismError`. Mirror the
  LLM pattern: `op.acknowledge` + rethrow typed errors raw; reserve `op.error` for unexpected ones.
  Blocks SVC-T1 (purchase-logic tests).
- [x] **UTIL-01 (P1, security)** `Sources/Cookies/CookieManager.swift` — With `lifetime == .zero`
  decode never expires, but Go inherits gorilla/securecookie's 30-day default MaxAge — the port has
  an unbounded replay window where Go bounds it. Default the decode bound to 30 days when lifetime
  is unset (or config-gate the deviation); fix the incorrect code comment and the test that locks
  in the divergence.
- [x] **SVC-03 (P1)** `Sources/FeatureFlags/PostHogConfig.swift` — Synthesized Codable rejects
  partial JSON (`{}` throws), violating the port's lenient-decode contract that its sibling
  `LaunchDarklyConfig` hand-implements. Add the same `decodeIfPresent ?? ""` init plus `{}` tests.
- [x] **OBS-04 (P2)** `Sources/Observability/Config.swift` — Synthesized Codable makes every key
  required, so the README-suggested partial Info.plist/JSON config fails to decode. Add
  `init(from:)` with `decodeIfPresent` + defaults; add a partial-decode test.
- [x] **CRY-01 (P2)** `Sources/Authentication/TOTP.swift` — `UInt64(floor(seconds / period))` traps
  for any pre-1970 date fed to `generate(secret:at:)`. Clamp negative time to 0 or throw.
- [x] **CRY-02 (P2)** `Sources/Identifiers/XID.swift` — `UInt32(Date().timeIntervalSince1970)`
  traps pre-1970 and post-2106; use `UInt32(truncatingIfNeeded:)` to match Go's wrap semantics.
  Also: `ProcessInfo.hostName` in the lazy `XIDGenerator.shared` init can block seconds on
  reverse-DNS, possibly on the main thread — derive machine-ID bytes from `gethostname(2)` or
  random bytes instead.
- [x] **CRY-03 (P2)** `Sources/Authentication/Base32.swift` — Decoder breaks at the *first* `=`,
  so mid-string padding silently truncates and decodes a prefix where Go rejects; also lengths
  `% 8 ∈ {1,3,6}` decode leniently. Only allow trailing padding; reject impossible lengths.
- [x] **OBS-05 (P2)** `Sources/Observability/Recording.swift` — `RecordingOperation.acknowledge(nil,…)`
  records nothing while `LiveOperation` logs info — tests can't observe the success-acknowledgement
  path. Record it.
- [x] **NET-06 (P2)** `Sources/Retry/RetryPolicy.swift` — `isTerminal` doesn't recognize
  `URLError.cancelled` despite HTTPClient's comment claiming it does; the loop is rescued only by
  the next `Task.sleep` throwing. Extend `isTerminal` (or map to `CancellationError` in HTTPClient).
- [x] **NET-07 (P2)** `Sources/CircuitBreaking/CircuitBreaker.swift` — `execute` exempts only
  `CancellationError`, not `URLError.cancelled` (inconsistent with HTTPClient). Share one
  "is cancellation" predicate across modules.
- [x] **UTIL-02 (P2)** `Sources/Version/Version.swift` — `StandardOutput.write` swallows write
  failures with `try?` inside a throwing API; also add `.sortedKeys` for stable JSON output.

---

## Wave 2 — API/seam changes (breaking; land before tagging 0.1.0)

- [ ] **NET-10 (P1)** Unify the duplicate `CircuitBreaker` protocols — `Sources/HTTPClient/CircuitBreaker.swift`
  vs `Sources/CircuitBreaking/CircuitBreaker.swift`: HTTPClient's seam is sync, the real breaker is
  an async actor, and both modules export colliding `CircuitBreaker`/`NoopCircuitBreaker` names.
  Make HTTPClient depend on CircuitBreaking (Package.swift), delete the local protocol + noop,
  await the async seam (or route through `CircuitBreaking.execute`). Fixes NET-02's policy for
  free; unblocks NET-03. Also re-check the breaker gate per retry attempt, not once per request.
- [ ] **OBS-10 (P1)** Typed attribute values — `Sources/Observability/Tracer.swift`, `Operation.swift`,
  `Logger.swift` all take `Any`, forcing `@unchecked Sendable` contortions (root cause of OBS-01)
  and stringifying everything. Introduce a small `Sendable` `AttributeValue` enum
  (string/int/double/bool/arrays + `ExpressibleBy*Literal` sugar) shared by span/log/operation
  surfaces. Record errors as typed `exception.type`/`exception.message` fields per OTel semconv.
- [ ] **OBS-11 (P1)** Add the shutdown/flush seam — `Pillars` has no `shutdown()`/`flush()` unlike
  Go's `Pillars.Shutdown`; the future OTLP exporter needs exactly this hook on
  `didEnterBackground`. Add an async `shutdown()` (default no-op) now so ObservabilityOTel adopts
  it without a breaking change. Shapes OBS-20.
- [ ] **OBS-12 (P2)** Span protocol gaps for the OTel adapter — add `setStatus(_:)` (Ok/Error/Unset),
  span-start options (kind: client/internal, initial attributes), and a sampling knob in
  `TracingConfig`. Feeds OBS-20. Same pass: name the tracer per component (today every signpost
  interval shares category `"spans"`/name `"span"`, so Instruments can't group by component —
  and the README's "interval named after the function" claim is wrong; fix both).
- [ ] **OBS-13 (P1)** Keys parity with Go — `Sources/Observability/Keys.swift` diverges from
  `platform-go/observability/keys` (`filter.*` vs `query_filter.*`, `connection.url` vs
  `connection_url`; missing `name`, `url`, `reason`, `search_query`, `validation_error`, `length`,
  `email.*`; Swift invents `path`). Cross-language dashboards silently miss. Reconcile and add a
  parity test pinning each constant's literal value.
- [ ] **CRY-10 (P1)** Rename the public `Hasher` protocol — `Sources/Cryptography/Hasher.swift`
  shadows `Swift.Hasher` for any importer, breaking manual `Hashable` conformances. Rename (e.g.
  `ContentHasher`) before the API calcifies; update conformances and tests.
- [ ] **OBS-14 (P2)** Split swift-log/swift-metrics interop out of the core — the core
  `Observability` target hard-depends on both packages even when native `.osLog`/`.signpost`
  providers are selected, in tension with the no-dep design intent. Move `SwiftLogLogger`/
  `SwiftMetricsProvider` to an interop target (mirroring the ObservabilityOTel separation).
- [ ] **NET-11 (P2)** EventStream request customization — SSE builds its own `URLRequest`, the
  WebSocket connector takes a bare URL; no way to pass auth headers (tests smuggle tokens through
  query params). Accept `URLRequest`/headers in `connect`. Prerequisite for NET-20 (Last-Event-ID).
- [ ] **NET-12 (P2)** `StandardCircuitBreaker` clock injection — make the actor generic over
  `Clock<Duration>` (default `ContinuousClock`) so half-open tests stop sleeping. Unblocks NET-22/23.
- [ ] **OBS-15 (P2)** Drop or namespace the bare `Counter`/`Gauge`/`Histogram` re-export
  typealiases (collide with SwiftUI `Gauge` etc.; `MetricTimer` is already prefixed for that reason).
- [ ] **SVC-10 (P2)** Standardize factory injection — `CapitalismConfig.provideManager` takes a
  prebuilt `Observer` while `LLMConfig` takes `Pillars`; pick one (recommend `Pillars`) repo-wide.
- [ ] **CRY-11 (P2)** `JWTVerificationKey`/`JWTParser` are non-`Sendable` solely due to the
  `SecKey` case, blocking actor storage of HMAC/ES256 parsers. Either `@unchecked Sendable` with a
  documented SecKey-immutability argument or split the RSA case into its own parser type.

---

## Wave 3 — Fill the shallow implementations

- [ ] **SVC-20 (P1)** Analytics: real transports — `SourceConfig.provideCollector()` throws
  `unsupportedProvider` for both `segment` and `posthog`; the whole config tree configures nothing.
  Implement thin URLSession+Codable reporters: PostHog `POST {endpoint}/batch`
  (`api_key`, `batch[]` of capture/identify with `$identify`/`$set`), Segment
  `POST https://api.segment.io/v1/batch` with `Authorization: Basic base64(writeKey + ":")`.
  In-memory buffering + flush-on-`close()`; wire the currently dead `SourceConfig.circuitBreaker`.
  While here: thread an `Observer` through `MultiSourceEventReporter` and log the
  unknown-source→noop fallback (Go does). Also fix the false doc claims that PostHog/Segment "ship
  no iOS SDK" (they do — the real rationale is the no-vendor-SDK policy; reword).
- [ ] **SVC-21 (P1)** FeatureFlags: a real provider — `makeFeatureFlagManager()` throws for both
  backends; every flag check in a real app is a noop. Implement a thin native PostHog manager
  against `POST {endpoint}/decide?v=3` (or `/flags?v=2`) with
  `{"api_key", "distinct_id", "person_properties"}`, parsing `featureFlags`/`featureFlagPayloads`
  into the five typed evaluators with fail-open defaults. Carry `CircuitBreakerConfig` in the wire
  shape when this lands (currently deliberately dropped). Note: `LaunchDarklyConfig.sdkKey` is a
  *server* credential — document the mobile-key distinction before any LD wiring.
- [ ] **SVC-22 (P1)** Notifications: the actual client-side surface — the only seam is the
  server-shaped `sendPush` the module doc admits an iOS app can never implement. Add a
  `NotificationCenterManager` protocol (requestAuthorization, remote-token async sequence,
  `schedule(_:)` via `UNUserNotificationCenter`) with live/noop/mock conformers; keep the existing
  wire-compatible payload types.
- [ ] **NET-20 (P1)** SSE reconnect per WHATWG — `id:` and `retry:` are parsed and dropped; any
  transport blip permanently kills the stream. Track them in `SSEFrameParser`, add a reconnecting
  wrapper (compose the Retry module) that re-dials with `Last-Event-ID`. Deps: NET-11.
  Same pass, spec fixes: strip a leading UTF-8 BOM in `SSELineSplitter`; don't dispatch frames
  with an empty data buffer (or document the divergence); validate
  `Content-Type: text/event-stream` on connect (a 200 HTML error page currently parses as silence).
- [ ] **NET-21 (P1)** WebSocket keepalive — `heartbeatInterval` is dead config and only server
  pings are answered; a NAT-dropped connection parks `receive()` forever. Add `sendPing` to the
  `WebSocketConnection` seam, run a heartbeat loop, close on pong timeout. Same seam extension lets
  `connect` confirm the handshake instead of returning a "connected" stream that can never fail.
- [ ] **NET-22 (P2)** Streaming-safe URLSession guidance — default/HTTPClient-built sessions kill
  quiet or long SSE streams (60s inter-byte idle; resource timeout 3× request). Ship/document a
  streaming session factory or build the session inside the connector.
- [ ] **OBS-20 (P1)** ObservabilityOTel: make it real — the target is an empty enum. Implement
  `OTelPillars.make(serviceName:endpoint:)` conformances + OTLP export, and a `W3CPropagation`
  traceparent/tracestate inject/extract (implementable dependency-free from `SpanContext`; could
  land in core now). Deps: OBS-10/11/12. Guard the trivial: `IDGen` can mint the all-zero
  trace/span id W3C declares invalid — loop until nonzero.
- [ ] **NET-23 (P1)** Trace-context propagation in HTTPClient — the operation opens a span but
  never injects `traceparent` into outbound headers, so distributed traces break at the client
  boundary. Inject from the current operation before `session.data(for:)`. Deps: the
  `W3CPropagation` piece of OBS-20.
- [ ] **OBS-21 (P2)** MetricKit beyond byte counts — `MetricKitDiagnostics` decodes nothing and has
  no consumer seam. Add a payload-handler closure/delegate, surface crash/hang diagnostics, and
  widen the `os(iOS)` gate to macOS 13 (MXMetricManager exists there for diagnostics).
- [ ] **NET-24 (P2)** HTTP retry semantics — honor `Retry-After` (numeric *and* HTTP-date; the LLM
  module has the same numeric-only gap) as a delay floor; convert retryable statuses (429/503) into
  retryable errors via the NET-03 classification seam; default retries to idempotent methods with
  per-request opt-in. Also: on cancellation mid-retry, surface `lastError` instead of a bare
  `CancellationError` (Go returns `lastErr`).
- [ ] **NET-25 (P2)** Bounded buffering — SSE/WS `AsyncThrowingStream`s and the SSE line buffer are
  unbounded (Go used a 64-slot channel). Pass `bufferingPolicy` and cap the line buffer.
- [ ] **NET-26 (P2)** HTTPClient failure metrics + `waitsForConnectivity` — failed requests emit no
  metrics (timeout storms invisible); expose `waitsForConnectivity`; document that
  `timeoutIntervalForRequest` is inter-byte idle, not Go's total-request timeout.
- [ ] **CRY-20 (P2)** Compression seam is empty for Go interop — neither Go wire format (zstd, s2)
  is decodable, so the one client-relevant flow (reading Go-produced payloads) is impossible.
  Product decision needed: vendored/native-adapter zstd decode vs adding an Apple-compatible
  algorithm on the Go side. Same pass: consider renaming the `.zlib` case (it's raw DEFLATE).

---

## Wave 4 — Repo-wide conventions, hygiene, and test debt

- [ ] **REPO-01 (P1)** CI — there is no `.github/` at all (platform-go runs 7 workflows). Add a
  workflow running `make build`, `make test`, `make lint` on macOS, plus `make build-ios` if
  feasible. Blocks REPO-02/03(publish).
- [ ] **REPO-02 (P2)** Coverage — add `make coverage` (`swift test --enable-code-coverage` +
  `llvm-cov export -format=lcov`) and codecov wiring once CI exists.
- [ ] **REPO-03 (P2)** Pin formatting — commit a `.swift-format` config (current style: 2-space
  indent) so `make format`/`make lint` don't drift across Xcode versions. Optional: DocC
  `make docs` target.
- [ ] **REPO-04 (P1)** README overhaul + port-tracking doc — README presents the package as
  observability-only (Status table lists 5 rows; Installation shows one product) while 24 products
  ship. Add a per-module status table and generalize the install snippet. Create a
  `PORT_PROGRESS.md` modeled on platform-rs's (tiered status: deep-port / pure-logic-done /
  real-local-backend / deferred-cloud, with "what's real" per module); record deliberate omissions
  there (PASETO, zstd/s2, `FromParams`, streaming LLM, etc.).
- [ ] **REPO-05 (P1)** Noop/Mock sweep — Go's rule: every service package ships noop + mock. Swift
  follows it in Analytics/FeatureFlags/LLM but not Cookies (no protocol seam at all — extract
  `CookieManaging` + Noop + Mock), HTTPClient, EventStream, Retry, CircuitBreaking (promote the
  private test fakes), Cryptography/Authentication (no way to stub `EncryptorDecryptor`, TOTP, JWT
  parsing, `ClientEncoder`), QRCodes (Noop only, no recording mock). Also SVC note: the actor
  mocks' `public var` handlers can't actually be set cross-actor in Swift 6 — add `setHandler`
  mutators or make them `let`.
- [ ] **REPO-06 (P2)** Lenient-decode sweep — enforce the "missing keys decode to Go zero values"
  contract everywhere: `Pagination`/`QueryFilteredResult` (`"data": null` throws today),
  `ObservabilityConfig` (OBS-04), FeatureFlags `PostHogConfig` (SVC-03). Add `{}`-decode tests as
  the convention.
- [ ] **REPO-07 (P1)** Cross-language interop fixtures — the port's compatibility claims are mostly
  untested against Go-produced bytes. Capture once from platform-go and pin: AES-GCM ciphertext,
  a securecookie-encoded value, a Go-minted xid (two already sit in the JWT test token's
  `jti`/`sub`), RFC3339Nano variable-precision timestamps for Filtering. JWT already has a Go
  token fixture — extend the pattern.
- [ ] **REPO-08 (P1)** Observability test debt — every existing test exercises the test doubles;
  zero coverage of `LiveObserver`/`LiveOperation` dual-write routing, `OSLogLogger.render`,
  signpost end-idempotence, or `IDGen` format. No concurrency tests: task-local parenting across
  `withTaskGroup`/`async let`, sibling spans, concurrent `op.set` (regression for OBS-01), partial
  config decode (OBS-04). Add a mock Span/Logger pair and the concurrency suite.
- [ ] **REPO-09 (P2)** Networking test debt — deterministic half-open re-trip test with
  `resetTimeout > window` (regression for NET-01; needs NET-12 clock), `RollingWindow` unit tests,
  backoff delay progression/cap/jitter bounds (current tests only count attempts), mid-stream SSE
  transport error, consumer-abandonment resource release (NET-04), HTTPClient metrics emission,
  cancellation-aware `FakeWebSocketConnection`.
- [ ] **REPO-10 (P2)** Crypto/auth test debt — full RFC 6238 Appendix B (18 vectors, 8 digits, all
  three algorithms; currently 6-digit spot checks), explicit `alg:"none"`/empty-signature JWT test,
  strict base64url rejection tests (pair with CRY-21), garbage + empty-input decompress for all
  four algorithms (guards an infinite-loop hang path in `AppleCompressor.stream`), Noop/Mock tests
  for LLM doubles, LLM error-classification fixture matrix (404, 400 routing, non-JSON body,
  URLError), StoreKit logic tests behind a `StoreKitClient` seam (deps: SVC-01/02).
- [ ] **REPO-11 (P2)** JWT/base64url strictness (grouped: CRY-21) — `Base64URLNoPad.decode` and
  Cryptography's `Base64URL` accept `+`/`/`/embedded `=` that RFC 7515 §2 / Go reject; wrong-typed
  `exp`/`nbf` treated as absent instead of malformed; non-string `aud` elements silently dropped;
  `crit` header not rejected. Optional parity-plus: `leeway` parameter for device clock drift.
  Also store the AES-GCM master key as `SymmetricKey` (best-effort zeroization) instead of `Data`.
- [ ] **REPO-12 (P2)** Small-module polish — Filtering: enforce `maxLimit` in `queryItems()`,
  delete stale "crossed CodingKeys" doc sentences, document dropped `FromParams`/`ToPagination`.
  QRCodes: fix the false linkerSettings doc claim. LLM: fix the garbled "salsa20-treated" doc
  sentence and the dead `unsupportedProvider` case; hand-write `encode(to:)` if the byte-for-byte
  re-encode claim stays. Package.swift: drop the empty `ObservabilityOTel` *product* until OBS-20
  lands (or give it a placeholder test target). Consider a shared `DurationWire` helper for the
  four copies of `Duration.wholeNanoseconds`.

---

## Wave 5 — New module ports (dependency-ordered; verdicts from the gap analysis)

Port order chosen so each module's dependencies exist first. All follow the settled pattern:
protocol seam + Config (lenient Codable) + live native impl + Noop + Mock + Observer threading +
CircuitBreaking config embedded for remote-backed modules.

- [ ] **PORT-01 (High, S–M)** `Secrets` — Keychain-backed `SecretSource { getSecret, close }`;
  `errSecItemNotFound` maps to the Go not-found/empty distinction; Info.plist/env source for debug.
- [ ] **PORT-02 (High, M)** `Cache` — `Cache<T>`/`BatchCache<T>` protocols; actor-backed memory
  (expiry, LRU) + disk layer via FileManager; drop Redis, keep the provider seam. Deps:
  Observability, CircuitBreaking, Encoding.
- [ ] **PORT-03 (Med, S)** `RateLimiting` — per-key token-bucket actor (`allow(key)`); client-side
  API throttling, sampling, retry pacing. Deps: Observability.
- [ ] **PORT-04 (Med, S–M)** `Files` — FileHandle/AsyncSequence line & chunk readers, windowed
  reads, typed `Decode<T>`, sandbox-rooted `Dir` (documents/app-group container). Deps: Encoding.
- [ ] **PORT-05 (Med, M)** `Fake` — hand-rolled no-dep fixture generators (corpus-based fakers);
  doubles as SwiftUI preview data. Deps: RandomKit, Identifiers.
- [ ] **PORT-06 (Med, S–M)** `Embeddings` — `Embedder` seam; on-device
  `NLEmbedding`/`NLContextualEmbedding` default + OpenAI HTTP backend mirroring the LLM pattern.
  Deps: HTTPClient. (Per the native-seam preference note, same shape as the LLM decision.)
- [ ] **PORT-07 (Med, M–L)** `Uploads` — FileManager backend + a remote seam shaped for URLSession
  *background upload* against presigned URLs (no S3 SDK); thin
  `CGImageSourceCreateThumbnailAtIndex` image helper. Deps: HTTPClient, CircuitBreaking.
- [ ] **PORT-08 (Med, L)** `Search` — port the two protocol families; text via SQLite FTS5 or
  CoreSpotlight, vector via in-memory brute-force cosine (fine on-device). Deps: PORT-06.
- [ ] **PORT-09 (Low, S)** `HealthCheck` — checker protocol + registry actor with TaskGroup +
  per-check timeouts; reachability (`NWPathMonitor`), disk-space, cache-ping checkers; feeds a
  debug screen.
- [ ] **PORT-10 (Low, S)** `Panicking` — injectable `fatalError`/`assertionFailure` seam;
  port opportunistically.
- [ ] **PORT-11 (deferred)** `Database` (ADAPT) — migration runner + typed access over local
  SQLite (raw sqlite3 or a seam for SwiftData/GRDB later); drop read/write split and admin
  Manager. Do when a concrete app needs it.
- [ ] **PORT-12 (deferred)** `TestSupport` (ADAPT of testutils) — test-image builders, shared
  `URLProtocol` stub, temp-dir fixtures; grow organically.

SKIP (server-only or obviated, documented here so nobody re-litigates): email, messagequeue,
routing, server, reflection, pointer (Swift optionals), errors (already `APIErrors` + native
`Error`), distributedlock (revisit only for app↔extension coordination), artifacts (empty in Go).

---

## Verified clean (no action; recorded so future reviews don't re-plow)

- Bitmask, Numbers, APIErrors, QRCodes: full Go parity, idiomatic, well-tested.
- JWT: signature-before-claims, alg pinned to key type (alg-confusion safe), constant-time
  comparisons. TOTP/HOTP: RFC 6238 + pquerna parity vectors pass. AES-GCM: fresh random 12-byte
  nonces, Go-compatible `nonce‖ct‖tag` layout. Randomness via `SecRandomCopyBytes`.
- LLM wire formats: correct Anthropic (`x-api-key`, `anthropic-version: 2023-06-01`, required
  `max_tokens`, system-hoisting) and OpenAI shapes; metric names and fallback semantics match Go.
  Streaming absent in both repos — not a gap.
- Capitalism's StoreKit 2 manager is genuinely live (modulo SVC-01/02).
- LICENSE present (AGPL-3.0, matches Go). Platform floors and Swift 6 language mode consistent
  across all targets.
