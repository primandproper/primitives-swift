/// # Analytics
///
/// Ported from platform-go's `analytics` package (`event_reporter.go` + `config/`, `noop/`, `mock/`,
/// `posthog/`, `segment/`, `multisource/`) — the client-relevant slice, per the iOS-only scope of this
/// port (see `PORTING.md`).
///
/// What travels over intact:
///   * ``EventReporter`` — the provider-seam protocol (``EventReporter/addUser(userID:properties:)``,
///     ``EventReporter/eventOccurred(event:userID:properties:)``,
///     ``EventReporter/eventOccurredAnonymous(event:anonymousID:properties:)``, ``EventReporter/close()``).
///   * ``NoopEventReporter`` and ``EventReporterMock`` — the no-op and test-double conformers.
///   * ``AnalyticsConfig``/``SourceConfig``/``ProxySourcesConfig`` — the wire-compatible `Codable`
///     config tree, including validation.
///   * ``MultiSourceEventReporter`` — the per-source routing/fan-out reporter (`multisource/reporter.go`).
///     It delegates to whatever ``EventReporter`` is registered per source and falls back to
///     ``NoopEventReporter`` for an unknown or unconfigured source (logging the fallback), exactly like
///     the Go original.
///   * ``SegmentEventReporter`` and ``PostHogEventReporter`` — thin URLSession + Codable reporters that
///     reimplement the Go SDKs' batch upload (`POST /v1/batch` / `POST {endpoint}/batch`) directly. Both
///     Segment and PostHog *do* ship first-party Swift SDKs; the port reimplements the HTTP call itself
///     purely because of this port's no-vendor-SDK policy. Events buffer in memory and flush on
///     batch-size/`close()`; the ``SegmentConfig``/``PostHogConfig`` circuit breaker is threaded through
///     ``SourceConfig/provideCollector(session:observer:metrics:)`` into each reporter.
///
/// Dropped (server-side, no iOS analogue): the `samber/do` DI registration (`config/do.go`,
/// `multisource/do.go`) — replaced everywhere in this port by plain constructor injection.
public enum Analytics {}
