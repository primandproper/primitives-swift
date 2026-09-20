# primitives-swift

A Swift port of [`primitives-go`](https://github.com/primandproper/primitives-go)'s toolkit — the same
conceptual API across languages, expressed idiomatically for Swift concurrency and iOS. It ships as a
set of **independent products** (32 libraries: observability, HTTP, event streams, crypto/auth,
analytics, feature flags, in-app purchase, and more) that you adopt à la carte. The design rules
are thin/native/no-third-party-SPM-SDK: URLSession + Codable, CryptoKit, StoreKit, UserNotifications,
with protocol seams shaped so a native or vendor adapter can wrap later.

**Scope: the device.** Swift builds apps here, never services — `platform-go` is the only server tier
there is. That makes this port unusual among the primitives ports in how *little* is out of scope:
`Database` is SQLite on device, `Search` is a `SQLiteTextSearcher` over it, `Capitalism` is StoreKit,
`HealthCheck` is reachability and disk space. What does not belong is anything that would put a vendor
API key on a handset, or that only makes sense beside server infrastructure. Talking to a service built
on `platform-go` is `platform-client-swift`'s job, not this package's.

Identifiers are the case worth naming, since this package used to carry a full xid
implementation: a server issues IDs and a client receives opaque strings, so minting one here
only risks having it rejected by the service you send it to. ``Fake/opaqueID()`` produces an
ID-*shaped* string for test data and deliberately parses nothing.

The keystone — and the deepest port — is **observability**. Its **Observer / Operation** abstraction is
a per-component bundle of a named logger and tracer, where `op.set(key, value)` records to **both** the
active span and a trace-enriched logger at once. On Apple platforms it lights up Instruments (spans) and
Console.app (logs) with zero infrastructure. Most of this README documents that module in depth; for a
per-module status of everything else see the [module table](#modules) below and
[`PORT_PROGRESS.md`](PORT_PROGRESS.md).

## Requirements

- Swift 6, iOS 16+ / macOS 13+
- No third-party SPM dependencies for the native path. The only external packages are
  [swift-metrics](https://github.com/apple/swift-metrics) (used by the core `Observability` metrics
  surface) and [swift-log](https://github.com/apple/swift-log) (used **only** by the optional
  `ObservabilityLog` interop product). Every other product is Foundation/Apple-framework only.

## Installation

Add the package once, then depend on just the products you need — each library is independent:

```swift
dependencies: [
    .package(url: "https://github.com/primandproper/primitives-swift.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Observability", package: "primitives-swift"),
        .product(name: "HTTPClient",    package: "primitives-swift"),
        .product(name: "Analytics",     package: "primitives-swift"),
        // …add any of the products in the module table below
    ]),
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and select the libraries you want. See the
[module table](#modules) for the full product list.

### Releases & versioning

Releases are plain **SemVer git tags** (bare `X.Y.Z`, no `v` prefix) — SPM resolves your version
requirement against them; there's no registry step. All products share one version.

While the package is pre-1.0, SemVer treats the **minor** as the breaking bump, so `from: "0.1.0"`
resolves `0.1.0 ..< 0.2.0` **only** (not up to `1.0`). For the safest pin during `0.x`, cap at the
next minor explicitly:

```swift
.package(url: "https://github.com/primandproper/primitives-swift.git", .upToNextMinor(from: "0.1.0")),
```

For the full versioning policy and the release process, see [`RELEASING.md`](RELEASING.md).

## Concepts

| Type | Role |
|---|---|
| `Pillars` | The three backends — `logger`, `tracer`, `metrics` — built once at startup. |
| `Observer` | One per component. Bundles a *named* logger + tracer so a component holds a single observability field. |
| `Operation` | The per-call bag from `observer.operation { … }`. `set` dual-writes to span **and** logger. |
| `ObservabilityConfig` | Codable config that selects backends and `bootstrap()`s the pillars. |

## Quick start

Build the pillars once (e.g. in your `App` init or a composition root), then hand `Observer`s to your
components via their initializers — there's no service locator; it's plain constructor injection.

```swift
import Observability

// 1. Bootstrap once. `.default` is OSLog + signposts — no infrastructure required.
let pillars = ObservabilityConfig.default.bootstrap()

// 2. Make a named observer per component.
let observer = makeObserver("ProfileService", pillars)

// 3. Use it.
final class ProfileService {
    private let observer: any Observer
    init(observer: any Observer) { self.observer = observer }

    func loadProfile(id: String) async throws -> Profile {
        // span name defaults to the calling function ("loadProfile(id:)")
        try await observer.operation { op in
            op.set(Keys.userID, id)            // -> span attribute + log field
            let profile = try await api.fetch(id)
            op.set("cache.hit", profile.cached)
            return profile
        }   // span ends automatically here
    }
}
```

What you get for free:

- An `OSSignposter` interval (statically named `"span"`, since signpost interval names must be a
  `StaticString`) carrying the function name, span kind, and ids in its message and grouped by
  component via the signpost category — visible as a span in **Instruments**.
- Log lines in **Console.app** carrying `span.id` / `trace.id`, so logs and traces correlate.
- Nested `operation` calls link parent → child automatically (see [Context propagation](#context-propagation)).

## The operation pattern

`set` is the workhorse — it lands on both pillars. When you need to target one, use `spanOnly` /
`logOnly`:

```swift
try await observer.operation("checkout") { op in
    op.set("order.id", orderID)          // span + log
    op.spanOnly("cart.raw", rawPayload)  // span only (verbose; keep it out of logs)
    op.logOnly("user.email", email)      // log only (don't put PII on spans)

    op.setValues([                        // batch form
        "item.count": items.count,
        "total.cents": totalCents,
    ])
}
```

`op.logger` and `op.span` are available if you need the underlying pillars directly inside an
operation.

### Errors

`op.error` logs against the operation's context, records the error on the span, and returns it
wrapped with your description — so you can `throw` it in one line:

```swift
try await observer.operation("loadProfile") { op in
    do {
        return try await api.fetch(id)
    } catch {
        throw op.error(error, "fetching profile")   // logs + records on span, then propagates
    }
}
```

Use `op.acknowledge(error, "…")` instead when you're handling the error and *not* propagating (it
logs/records but returns nothing).

### Manual begin / end (escape hatch)

The closure form is preferred — it can't leak a span. When you genuinely can't wrap your work in a
closure, start and end manually:

```swift
let op = observer.begin()       // name defaults to #function
defer { op.end() }
op.set("phase", "warmup")
// … note: task-local context does NOT auto-propagate to nested async work in this form.
```

## Logging directly

Outside an operation, use the pillar logger. It has value semantics — every `with*` returns a new
logger:

```swift
let log = pillars.logger.withName("Sync")
log.info("starting sync")
log.withValue("batch", 12).debug("processing batch")
log.error("sync failed", error)
```

## Metrics

`pillars.metrics` vends the four swift-metrics instrument kinds:

```swift
pillars.metrics.counter("requests.total", tags: ["endpoint": "profile"]).increment()
pillars.metrics.gauge("queue.depth").record(42)
pillars.metrics.histogram("response.bytes").record(1_024)
pillars.metrics.timer("request.duration").recordNanoseconds(elapsed)
```

> Metrics route through swift-metrics' process-wide factory. Until you call `MetricsSystem.bootstrap`
> (or use the OTel target, below), instruments are no-ops — safe to call, nothing emitted.

## Configuration & backends

`ObservabilityConfig` is plain `Codable` — build it in code or decode it from Info.plist / JSON
(unlike a platform-go service, iOS apps don't configure from the environment).

```swift
var config = ObservabilityConfig(serviceName: "MyApp")
config.logging.provider = .osLog       // .osLog (default) | .noop
config.tracing.provider = .signpost    // .signpost (default) | .noop
config.metrics.provider = .swiftMetrics // .swiftMetrics (default) | .noop
let pillars = config.bootstrap()
```

| Pillar | Default | Alternatives |
|---|---|---|
| Logging | `.osLog` (native `os.Logger`) | `.noop`. For swift-log, use the `ObservabilityLog` product and construct `SwiftLogLogger` directly (no config case). |
| Tracing | `.signpost` (Instruments) | `.noop` |
| Metrics | `.swiftMetrics` | `.noop` |

For tests or previews, skip config entirely: `Pillars.noop`.

### OpenTelemetry & trace propagation

W3C `traceparent`/`tracestate` inject/extract for outbound `URLSession` requests ships in **core
`Observability`** (`W3CPropagation`) — it needs no OTel dependency, and `HTTPClient` uses it to
propagate the active span across the client boundary, so distributed traces stay linked with your Go
services.

The `ObservabilityOTel` target is an **empty placeholder**: the OTLP *exporter* (shipping spans/metrics
to an external collector) was deliberately dropped. The port's observability is native-first (os_log +
Instruments + MetricKit), nothing is lost at the propagation layer, and the exporter is the one heavy
dependency-bearing piece that cuts against the thin/native/no-dep rule. Revisit only if a concrete app
needs a cloud OTel backend.

## Context propagation

There's no `context.Context` to thread. Instead, the closure form of `operation` installs the new
span's context as a task-local (`SpanContextStore.current`) for the duration of the body. Any
`operation` started inside — even across `await` — picks it up as its parent automatically:

```swift
try await observer.operation("parent") { _ in
    try await observer.operation("child") { _ in
        // child.span.context.parentSpanID == parent's spanID, same traceID
    }
}
```

This is the implicit equivalent of primitives-go returning a new `ctx` from `Begin`.

## iOS integration

App composition root, sharing one set of pillars:

```swift
import SwiftUI
import Observability

@main
struct MyApp: App {
    let pillars = ObservabilityConfig.default.bootstrap()

    var body: some Scene {
        WindowGroup {
            ProfileView(
                model: ProfileViewModel(observer: makeObserver("ProfileView", pillars))
            )
        }
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: Profile?
    private let observer: any Observer
    init(observer: any Observer) { self.observer = observer }

    func load(id: String) async {
        await observer.operation { op in
            do {
                profile = try await api.fetch(id)
                op.set("loaded", true)
            } catch {
                op.acknowledge(error, "loading profile for view")
            }
        }
    }
}
```

### MetricKit diagnostics

The iOS analogue of primitives-go's profiling pillar. Subscribe at launch to receive MetricKit's daily
power/performance and crash-diagnostics payloads:

```swift
let diagnostics = MetricKitDiagnostics(logger: pillars.logger)
diagnostics.start()    // call diagnostics.shutdown() to unsubscribe
```

## Testing

`RecordingObserver` captures every observation instead of emitting it, so you can assert on what your
code reported — pillar routing, values, ordering, errors:

```swift
import Testing
@testable import Observability

@Test func recordsUserID() async {
    let observer = recordingObserver("test")

    await observer.operation("loadProfile") { op in
        op.set(Keys.userID, "abc")
    }

    let op = observer.operations.first!
    #expect(op.observations.contains { $0.key == Keys.userID && $0.pillar == .both })
}
```

`RecordingOperation` also exposes `recordedErrors`, `ended`, and helpers like `value(forKey:)` and
`keys(on:)`.

## Make targets

```bash
make setup       # resolve dependencies
make format      # swift-format, in place   (alias: make fmt)
make lint        # swift-format --strict lint
make build       # swift build
make build-ios   # xcodebuild for a generic iOS device
make test        # swift test (host)
make test-ios    # xcodebuild test on a simulator (override: IOS_SIM="iPhone 16 Pro")
make clean
```

## Modules

Every product is independent; adopt them à la carte. Tiers follow
[`PORT_PROGRESS.md`](PORT_PROGRESS.md), which records "what's real" and every deliberate deferral per
module.

**Legend** — 🟢 real backend / done · 🟡 real backend with a deferred second backend or documented gap ·
⚪️ placeholder / deferred.

| Product | Tier | State — what's real |
|---|---|---|
| `Observability` | deep port | 🟢 Observer/Operation, OSLog logger + signpost tracer + swift-metrics, noop, typed `AttributeValue`, W3C `traceparent` propagation, MetricKit diagnostics (minimal) |
| `ObservabilityLog` | deep port | 🟢 `SwiftLogLogger` swift-log interop (split out so the native path is swift-log-free) |
| `ObservabilityOTel` | placeholder | ⚪️ empty stub — OTLP exporter **dropped** (OBS-20); propagation lives in core instead |
| `Bitmask` | pure-logic | 🟢 bitmask set ops, full Go parity |
| `Numbers` | pure-logic | 🟢 numeric helpers + range clamping |
| `Version` | pure-logic | 🟢 build/version info, JSON + text rendering |
| `RandomKit` | pure-logic | 🟢 `SecRandomCopyBytes` generator, Base32, slice helpers; noop |
| `APIErrors` | pure-logic | 🟢 `APIResponse` / `ErrorCode` types |
| `Filtering` | pure-logic | 🟡 pagination / query-filter / RFC3339; `FromParams`/`ToPagination` **not ported** |
| `Encoding` | pure-logic | 🟢 `ClientEncoder` + JSON encoder, content-type negotiation |
| `Retry` | pure-logic | 🟢 exponential backoff (jitter/cap), `Retry-After` floor; noop |
| `Fake` | pure-logic | 🟢 corpus-based fixture generators + seeded SwiftUI-preview data |
| `Cryptography` | native backend | 🟢 CryptoKit AES-GCM (Go-byte-compatible) + SHA-2/checksum hashers; no PASETO |
| `Authentication` | native backend | 🟢 JWT verify, TOTP/HOTP (RFC 6238), Base32/Base64URL |
| `Cookies` | native backend | 🟢 HMAC-SHA256 signed cookies (securecookie-compatible) |
| `CompressionKit` | native backend | 🟡 Apple `lzfse`/`lz4`/`lzma`/`zlib`; `zstd`/`s2` decode-but-throw (no Go wire interop, CRY-20) |
| `QRCodes` | native backend | 🟢 CoreImage QR + TOTP-URI QR; noop |
| `CircuitBreaking` | native backend | 🟢 in-memory rolling-window breaker (clock-injectable) + keyed; noop |
| `HTTPClient` | native backend | 🟢 URLSession client with Retry + CircuitBreaking, `traceparent` injection, failure metrics |
| `EventStream` | native backend | 🟢 URLSession SSE (WHATWG reconnect, `Last-Event-ID`) + WebSocket (keepalive), bounded buffers; noop |
| `Notifications` | native backend | 🟡 live `UNUserNotificationCenter` client seam + noop + mock; server-side push **send** is noop-by-design |
| `Capitalism` | native backend | 🟡 live StoreKit 2 purchase manager + noop + mock; RevenueCat backend **deferred** |
| `Secrets` | native backend | 🟢 Keychain-backed `SecretSource` + env/Info.plist debug source; noop + mock |
| `Cache` | native backend | 🟢 actor memory (TTL + LRU) + FileManager disk `Cache<T>`/`BatchCache<T>`; Redis dropped; noop + mock |
| `RateLimiting` | native backend | 🟢 clock-injectable per-key token-bucket actor; noop + mock |
| `Files` | native backend | 🟢 AsyncSequence line/chunk/windowed readers, `Decode<T>`, sandbox-rooted `Dir`; noop + mock |
| `Embeddings` | native backend | 🟢 on-device `NLEmbedding` + OpenAI URLSession backend; noop + mock |
| `Uploads` | native backend | 🟢 FileManager local + presigned-URL background-upload seam (S3 dropped) + ImageIO thumbnails; noop + mock |
| `Search` | native backend | 🟢 SQLite FTS5 text + in-memory cosine vector (Embedder-backed); noop + mock |
| `HealthCheck` | native backend | 🟢 checker + registry actor (per-check timeouts), reachability/disk-space checkers; noop + mock |
| `Analytics` | cloud transport | 🟢 Segment + PostHog URLSession reporters (buffer/flush, circuit breaker); noop + mock |
| `FeatureFlags` | cloud transport | 🟡 live PostHog evaluator; LaunchDarkly **deferred** (mobile-key mismatch); noop + mock |

Not yet ported: `Database` and `TestSupport` (**deferred** until a concrete app needs them); and the
server-only **SKIP** list — email, messagequeue, routing, server, reflection, pointer, errors,
distributedlock, artifacts. Full rationale in [`PORT_PROGRESS.md`](PORT_PROGRESS.md).
