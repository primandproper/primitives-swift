# platform-swift

A Swift port of [`platform-go`](https://github.com/primandproper/platform-go)'s toolkit, starting
with **observability**. Same conceptual API across languages, expressed idiomatically for Swift
concurrency and iOS.

The keystone is the **Observer / Operation** abstraction: a per-component bundle of a named logger
and tracer, where `op.set(key, value)` records to **both** the active span and a trace-enriched
logger at once. On Apple platforms it lights up Instruments (spans) and Console.app (logs) with zero
infrastructure; point it at an OpenTelemetry collector when you want parity with your backend
services.

## Requirements

- Swift 6, iOS 16+ / macOS 13+
- Depends on [swift-log](https://github.com/apple/swift-log) and
  [swift-metrics](https://github.com/apple/swift-metrics)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/primandproper/platform-swift.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Observability", package: "platform-swift"),
    ]),
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and select the `Observability` library.

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

- An `OSSignposter` interval named after the function, visible as a span in **Instruments**.
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
(unlike platform-go, iOS apps don't configure from the environment).

```swift
var config = ObservabilityConfig(serviceName: "MyApp")
config.logging.provider = .osLog       // .osLog (default) | .swiftLog | .noop
config.tracing.provider = .signpost    // .signpost (default) | .noop
config.metrics.provider = .swiftMetrics // .swiftMetrics (default) | .noop
let pillars = config.bootstrap()
```

| Pillar | Default | Alternatives |
|---|---|---|
| Logging | `.osLog` (native `os.Logger`) | `.swiftLog` (bridge to an existing swift-log setup), `.noop` |
| Tracing | `.signpost` (Instruments) | `.noop` |
| Metrics | `.swiftMetrics` | `.noop` |

For tests or previews, skip config entirely: `Pillars.noop`.

### OpenTelemetry (optional)

The `ObservabilityOTel` target will provide OTLP-exporting adapters and W3C `traceparent`
inject/extract for outbound `URLSession` requests, so iOS traces/metrics land in the same stack as
your Go services. It's a documented stub today — the OpenTelemetry-swift dependency is intentionally
kept out of the core graph until those adapters land.

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

This is the implicit equivalent of platform-go returning a new `ctx` from `Begin`.

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

The iOS analogue of platform-go's profiling pillar. Subscribe at launch to receive MetricKit's daily
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

## Status

| Piece | State |
|---|---|
| Observer / Operation, Logger, Tracer, Metrics, Config, Keys | done |
| OSLog + Signpost backends, noop, swift-log interop | done |
| `RecordingObserver` + tests | done |
| MetricKit diagnostics | minimal |
| `ObservabilityOTel` (OTLP export, W3C propagation) | stub |
