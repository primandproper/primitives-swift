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
///     Its composition logic is real and useful even without a live vendor backend: it delegates to
///     whatever ``EventReporter`` is registered per source and falls back to ``NoopEventReporter`` for
///     an unknown or unconfigured source, exactly like the Go original.
///
/// What gets the **salsa20 treatment** (decodes, factory throws):
///   * ``SegmentConfig`` and ``PostHogConfig`` decode/encode Go's exact wire shape, but
///     ``SourceConfig/provideCollector()`` throws ``AnalyticsError/unsupportedProvider(_:)`` for both —
///     neither Segment nor PostHog ships a first-party Swift/iOS SDK, and vendoring their server-side Go
///     SDKs (or a heavy third-party client) is out of scope for this port. Wire up a real backend only
///     if a flow needs one.
///
/// Dropped (server-side, no iOS analogue): the `samber/do` DI registration (`config/do.go`,
/// `multisource/do.go`) — replaced everywhere in this port by plain constructor injection.
public enum Analytics {}
