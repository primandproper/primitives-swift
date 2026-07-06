# platform-swift — Port Progress

A static survey of all 35 shipping products (targets in `Package.swift`), verified by reading each
module's `Config`, `Provider`/protocol seam, live-backend, and `Noop`/`Mock` source plus the gap
markers and deferral notes carried in `TODO.md`. This is a code survey (file presence, provider
routing, doc-comment deferral markers), not a `swift test` run — see *Caveats* at the bottom.

Modeled on the sibling [`platform-rs/PORT_PROGRESS.md`](../platform-rs/PORT_PROGRESS.md) tiering, adapted
for the Swift port's native-first stance (URLSession + Codable, CryptoKit, StoreKit, UserNotifications —
no third-party SPM SDKs).

## TL;DR

- **One deep port:** `Observability` (~1,440 LOC, 12 files) genuinely mirrors platform-go's
  observability — the `Observer` / `Operation` / `Recording` / `Keys` / typed-`AttributeValue` layer,
  OSLog + signpost native backends, noop, and W3C `traceparent` propagation. This is the keystone and the
  only module ported in real depth. `ObservabilityLog` is its swift-log interop split-out.
- **Most service modules now have a real backend.** This port has moved past "trait + noop": `Analytics`,
  `FeatureFlags`, and `LLM` ship thin native URLSession transports against the real vendor HTTP APIs;
  `Notifications` gained a live on-device `UNUserNotificationCenter` client seam; `Capitalism` drives
  StoreKit 2 for real. The "shallow copy of interfaces + noop" mental model no longer holds for the
  service tier — it holds only for the *deferred second backend* inside a few modules (LaunchDarkly,
  RevenueCat, server-side push send).
- **The rest** splits into fully-implemented pure-logic utilities and modules with a real on-device
  native backend (CryptoKit, StoreKit, Compression framework, CoreImage, in-memory state machines).
- **One genuine placeholder:** `ObservabilityOTel` is an empty stub — the OTLP exporter (OBS-20) was
  deliberately **dropped**. W3C propagation, the one piece worth keeping, already shipped in core.
- **Wave 5 landed 10 new module ports (2026-07-06).** `Secrets` (Keychain), `Cache` (memory TTL/LRU +
  FileManager disk, Redis dropped), `RateLimiting` (token-bucket actor), `Files` (AsyncSequence readers +
  sandbox `Dir`), `Fake` (corpus fixtures), `Embeddings` (on-device `NLEmbedding` + OpenAI), `Uploads`
  (FileManager + presigned-URL background upload, S3 dropped), `Search` (SQLite FTS5 + in-memory cosine),
  `HealthCheck` (registry actor), and `Panicking` (crash seam) — all native-first, each with seam + Noop +
  Mock + lenient Config. Only `Database` and `TestSupport` remain deferred.

## Status by tier (true state)

### Tier 0 — Reference / deep port
| Product | LOC | What's real |
|---|---|---|
| `Observability` | ~1441 | Logging/tracing/metrics protocol seams + native **OSLog** logger and **OSSignposter** tracer + swift-metrics metrics + noop backends, **plus** the platform-go-faithful `Observer`/`Operation`/`RecordingObserver`/`Keys`/`errors` layer, a typed `AttributeValue` enum, and `W3CPropagation` (traceparent/tracestate inject/extract on `URLRequest`). The involved port. |
| `ObservabilityLog` | ~38 | `SwiftLogLogger` — a `Logger` conformance bridging to swift-log, split into its own target so the native `.osLog` path carries no swift-log dependency (OBS-14). Real, thin. |

### Tier 1 — Pure-logic utilities (fully implemented, no backend concept)
Real logic, no provider abstraction and no external service. These are *done*, not stubs.

| Product | LOC | What's real |
|---|---|---|
| `Bitmask` | ~123 | Generic bitmask set operations. Full Go parity. |
| `Numbers` | ~97 | Numeric helpers + range clamping. |
| `Version` | ~133 | Build/version info, JSON/text rendering (stable `.sortedKeys`). |
| `Identifiers` | ~185 | `XID` generator (Go xid wire-compatible; wrap-safe timestamp; `gethostname`-derived machine id). |
| `RandomKit` | ~207 | `SecRandomCopyBytes`-backed generator, Base32, slice helpers; noop generator. |
| `APIErrors` | ~125 | `APIResponse` / `ErrorCode` types (depends on Filtering for pagination shape). |
| `Filtering` | ~234 | `Pagination`, `QueryFilter`, `QueryFilteredResult`, `SortDirection`, variable-precision RFC3339 parsing. |
| `Encoding` | ~230 | `ClientEncoder` protocol + `JSONClientEncoder`, content-type negotiation. |
| `Retry` | ~311 | `ExponentialBackoffPolicy` (jitter/cap), `Retry-After` delay floor, terminal-error classification; noop policy. |
| `Fake` | ~472 | Corpus-based fixture generators (names/email/lorem/ids/dates/ranges) over `RandomKit`, plus a seeded `SplitMix64`-backed generator for deterministic SwiftUI preview data. |
| `Panicking` | ~290 | Injectable `Panicker` seam wrapping `fatalError`/`assertionFailure`/`preconditionFailure`; live + noop + recording/throwing mock (so tests assert a panic without trapping). |

### Tier 2 — Real native on-device backend (offline / no cloud SaaS)
Working implementations backed by an Apple framework or an in-memory state machine. The noop doubles as
the mock where a seam exists. Network modules here are generic transports (URLSession), offline-testable
via an injected session / `URLProtocol` stub.

| Product | LOC | Real backend | Deferred / notes |
|---|---|---|---|
| `Cryptography` | ~420 | CryptoKit **AES-GCM** (`nonce‖ct‖tag`, Go-byte-compatible) + SHA-2 / checksum hashers (`ContentHasher`) | — |
| `Authentication` | ~717 | **JWT** verify (sig-before-claims, alg pinned to key type), **TOTP/HOTP** (RFC 6238), Base32/Base64URL | PASETO **not ported** (Go has it) |
| `Cookies` | ~519 | **HMAC-SHA256** signed-cookie encode/decode (securecookie-compatible, 30-day default bound) | — |
| `CompressionKit` | ~303 | Apple **Compression** framework: `lzfse`/`lz4`/`lzma`/`zlib` (raw DEFLATE) | `zstd`/`s2` **decode but throw** — Apple has no codec; not Go-wire-interoperable (CRY-20 dropped) |
| `QRCodes` | ~232 | CoreImage QR builder + TOTP-URI QR builder; noop | — |
| `CircuitBreaking` | ~646 | In-memory rolling-window state machine (`StandardCircuitBreaker`, clock-injectable) + keyed variant; noop | — |
| `HTTPClient` | ~623 | Real `URLSession` client with Retry + CircuitBreaking integration, `traceparent` injection, retryable-status classification, failure metrics | — |
| `EventStream` | ~1423 | Real `URLSession` **SSE** (WHATWG-compliant reconnect, `Last-Event-ID`, BOM strip) + **WebSocket** (keepalive/ping) streams, bounded buffering; noop | — |
| `Notifications` | ~705 | **Live `UNUserNotificationCenter` client seam** (`NotificationCenterManager`: auth, device-token async sequence, local scheduling) + noop + mock | `PushNotificationSender` (server→device APNs/FCM *send*) is **server-shaped, noop/mock only** by design — an iOS app never sends its own push |
| `Capitalism` | ~835 | **StoreKit 2** purchase manager (live: products, purchase, entitlements, transaction finishing) + noop + mock | RevenueCat backend **deferred** (config decodes; `provideManager` throws for it) |
| `Secrets` | ~495 | **Keychain** `SecretSource` (Security framework) preserving Go's missing-vs-empty split (`errSecItemNotFound` → not-found) + env/Info.plist debug source + noop + mock | GCP Secret Manager / AWS SSM / k8s backends **dropped** (provider strings decode, factory throws) |
| `Cache` | ~756 | Actor **in-memory** cache (TTL expiry + LRU) and **FileManager disk** layer (values via `Encoding`), generic `Cache<T>`/`BatchCache<T>` + noop + mock | **Redis dropped**; provider seam + embedded `CircuitBreakerConfig` kept for a future remote adapter |
| `RateLimiting` | ~373 | Per-key **token-bucket actor** (`allow(key:count:)`), generic over `Clock<Duration>` (default `ContinuousClock`) so tests don't sleep + noop + mock | Redis sliding-window backend **dropped**; provider seam kept |
| `Files` | ~743 | **AsyncSequence** line / chunk / windowed readers (class iterator closes the `FileHandle` on early abandonment), typed `Decode<T>`, sandbox-rooted `Dir` rejecting `..`/absolute/symlink escapes + noop + mock | — |
| `Embeddings` | ~830 | **On-device `NLEmbedding`** (NaturalLanguage) default + **OpenAI** `POST /embeddings` URLSession backend (mirrors `LLM`'s pattern, shared metric/error semantics) + noop + mock | Ollama / Cohere backends **dropped**; embedded `CircuitBreakerConfig` carried-but-inert (LaunchDarkly precedent) |
| `Uploads` | ~978 | **FileManager** local uploader (sandbox root, traversal-rejecting) + **presigned-URL** `URLSession` upload seam shaped for background uploads + ImageIO thumbnailer + noop + mock | **S3 / gocloud provider set dropped**; presigned seam + embedded `CircuitBreakerConfig` kept |
| `Search` | ~1183 | **Text** via SQLite **FTS5** (system `SQLite3`, bm25 + porter stemming, in-process testable) + **vector** brute-force **cosine/dot/euclidean** in-memory actor (Embedder-backed convenience) + noop + mock per seam | Elasticsearch/Algolia (text) + pgvector/Qdrant (vector) **dropped**; Go's `circuitBreakerConfig` decode-and-ignored (native, no remote call) |
| `HealthCheck` | ~519 | `Checker` seam + **registry actor** fanning checks over a `TaskGroup` with hard per-check timeouts; reachability (`NWPathMonitor`), disk-space, and generic closure checkers + noop + mock | Go's DB/cache/MQ checkers collapsed to one closure checker (`Cache` deliberately not imported — app wires a cache-ping later) |

### Tier 3 — Real cloud/remote transport (thin native URLSession against a SaaS HTTP API)
Not vendor SDKs — hand-written `URLSession` + `Codable` clients hitting the same HTTP surface the vendor
SDKs use (the repo's no-vendor-SDK rule). Builds/tests offline via an injected `URLSession`; each ships a
`Noop` and a `Mock`, and a lenient-decoding `Config`.

| Product | LOC | Real backend(s) | Deferred |
|---|---|---|---|
| `Analytics` | ~1224 | **Segment** (`POST api.segment.io/v1/batch`, Basic auth) + **PostHog** (`POST {endpoint}/batch`) reporters with in-memory buffering, flush-on-`close()`, wired circuit breaker; multi-source proxy reporter | — (unknown provider → noop, as Go) |
| `FeatureFlags` | ~847 | **PostHog** live evaluator (`POST {endpoint}/flags/?v=2`, five typed flag evaluators, fail-open); noop + mock | **LaunchDarkly** throws `unsupportedProvider` — its mobile SDK needs a *mobile* key, not the server `sdkKey` carried in config (deliberate; documented) |
| `LLM` | ~872 | **Anthropic** (`x-api-key`, `anthropic-version`, system-hoisting) + **OpenAI** chat wire mappings over URLSession; noop + mock | **Streaming** deferred (absent in Go too — not a gap); tools/embeddings/multimodal one layer down |

### Tier 4 — Placeholder / deferred (no real backend yet, by design)
| Product | State | Intended backend |
|---|---|---|
| `ObservabilityOTel` | **Empty placeholder** (`enum ObservabilityOTelPlanned {}` + a design sketch in doc comments). Ships as a product but exports nothing runnable. | OTLP-exporting `Logger`/`Tracer`/`MetricsProvider` adapters — **DROPPED (OBS-20, 2026-07-05)**: the exporter is the one heavy dependency-bearing piece, against the thin/native/no-dep rule; native-first observability loses nothing at the propagation layer because `W3CPropagation` already shipped in core. Revisit only for a concrete cloud-OTel-backend need. |

## Deliberate omissions & deferrals (recorded so future reviews don't re-plow)

- **PASETO** — not ported. `Authentication` ships JWT + TOTP only.
- **zstd / s2 compression** — `CompressionKit` recognizes the two Go wire formats (config strings still
  decode) but **throws** on use; Apple's Compression framework implements neither and a vendored libzstd
  is against the no-dep rule. So the port cannot exchange compressed bytes with the Go service. (CRY-20,
  dropped 2026-07-05 — no client flow needs it.)
- **`FromParams` / `ToPagination`** (`Filtering`) — the Go query-param binding helpers are **not ported**;
  the module exposes `queryItems()` for outbound building only. (Tracked under REPO-12 to be documented in
  the module's own doc comments.)
- **Streaming LLM** — deferred; absent in platform-go as well, so not a regression. Anthropic/OpenAI
  non-streaming `complete` is real.
- **OTLP exporter** (`ObservabilityOTel`) — dropped (see Tier 4). The target is an empty placeholder; its
  empty *product* is slated for removal from `Package.swift` (REPO-12) once tooling allows.
- **Redis-backed `Cache`** — `Cache` ships actor memory (TTL + LRU) + a FileManager disk layer; the Redis
  backend is **intentionally dropped** (provider seam + embedded `CircuitBreakerConfig` kept for a future
  remote adapter).
- **LaunchDarkly** (`FeatureFlags`) and **RevenueCat** (`Capitalism`) — second backends deferred; configs
  decode and validate, but the factory throws for them.
- **Server-side push send** (`Notifications.PushNotificationSender`) — noop/mock only, by design; sending
  to APNs/FCM is a server concern.

### Not ported — SKIP list (server-only or obviated; from TODO.md Wave 5)
Documented so nobody re-litigates: **email**, **messagequeue**, **routing**, **server**, **reflection**,
**pointer** (Swift optionals cover it), **errors** (covered by `APIErrors` + native `Error`),
**distributedlock** (revisit only for app↔extension coordination), **artifacts** (empty in Go).

### Planned but not yet started (TODO.md Wave 5 port order)
All ten Wave 5 module ports **landed (2026-07-06)**: `Secrets`, `Cache`, `RateLimiting`, `Files`, `Fake`,
`Embeddings`, `Uploads`, `Search`, `HealthCheck`, `Panicking` (see Tiers 1–2 above). Only `Database`
(ADAPT — SQLite migration runner) and `TestSupport` (ADAPT of testutils) remain **deferred** until a
concrete app needs them.

## Divergence from platform-go

- **Native-first, no vendor SDKs.** Where Go embeds vendor clients (posthog-go, Segment, Stripe/RevenueCat,
  LaunchDarkly OpenFeature, APNs/FCM senders), the port either talks the same HTTP surface directly
  (Analytics, FeatureFlags, LLM) or uses the equivalent Apple framework (StoreKit, UserNotifications,
  CryptoKit, Compression, CoreImage). Server-only vendor behavior (push *send*) stays noop-by-design.
- **Config from Codable, not the environment.** iOS apps decode config from Info.plist / JSON with lenient
  decoding to Go zero values, rather than reading env vars.
- **swift-metrics retained in core.** OBS-14 split swift-log out to `ObservabilityLog` but kept the
  swift-metrics dependency in core `Observability` (every consumer calls its instrument types directly);
  the backend-agnostic instrument abstraction was to ride along with the now-dropped OTLP port, so there's
  no forcing function. Accepted minor deviation from the strict no-dep intent.

## Caveats

- This is a **static read** (file presence, provider routing, doc-comment deferral markers, LOC), not a
  `swift build` / `swift test` run. "Real" means "contains a genuine implementation wired into the
  `provide*`/factory path," not "verified green in this survey." The suite is green at the surveyed base
  commit: 35 modules, 1174 tests passing (Wave 5 added 10 modules / +279 tests over the Wave-4 close).
- LOC counts are `Sources/<module>/**/*.swift` including inline doc comments.
- Surveyed from the settled `fable_fixes` line (base `28953e6`), which carries all completed Wave 1–3
  work. If you are reading this from an older worktree base, the service-tier backends above may not yet
  be present in that checkout's `Sources/`.
