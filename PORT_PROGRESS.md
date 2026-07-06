# platform-swift — Port Progress

A static survey of all 25 shipping products (targets in `Package.swift`), verified by reading each
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
- **Redis-backed `Cache`** — the `Cache` module is **not yet ported at all** (planned as PORT-02:
  actor-backed memory + FileManager disk layer, Redis intentionally dropped, provider seam kept).
- **LaunchDarkly** (`FeatureFlags`) and **RevenueCat** (`Capitalism`) — second backends deferred; configs
  decode and validate, but the factory throws for them.
- **Server-side push send** (`Notifications.PushNotificationSender`) — noop/mock only, by design; sending
  to APNs/FCM is a server concern.

### Not ported — SKIP list (server-only or obviated; from TODO.md Wave 5)
Documented so nobody re-litigates: **email**, **messagequeue**, **routing**, **server**, **reflection**,
**pointer** (Swift optionals cover it), **errors** (covered by `APIErrors` + native `Error`),
**distributedlock** (revisit only for app↔extension coordination), **artifacts** (empty in Go).

### Planned but not yet started (TODO.md Wave 5 port order)
`Secrets` (Keychain), `Cache`, `RateLimiting`, `Files`, `Fake`, `Embeddings` (NLEmbedding + OpenAI),
`Uploads`, `Search`, `HealthCheck`, `Panicking`; `Database` / `TestSupport` deferred until a concrete app
needs them.

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
  `provide*`/factory path," not "verified green in this survey." The suite is reported green at the
  surveyed base commit (`TODO.md`: 24 modules, ~9.9k LOC).
- LOC counts are `Sources/<module>/**/*.swift` including inline doc comments.
- Surveyed from the settled `fable_fixes` line (base `28953e6`), which carries all completed Wave 1–3
  work. If you are reading this from an older worktree base, the service-tier backends above may not yet
  be present in that checkout's `Sources/`.
