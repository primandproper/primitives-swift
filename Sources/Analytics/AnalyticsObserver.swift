import Observability

/// A silent default ``Observer`` for the analytics reporters, so a reporter is usable un-instrumented.
///
/// There is no shared no-op `Observer` conformer in ``Observability`` (the module ships `NoopLogger`
/// and `NoopTracer` but leaves composing them to the caller), so this wraps them in a ``LiveObserver``
/// — the same move ``CircuitBreaking`` makes when defaulting a breaker's logger/metrics.
public func defaultAnalyticsObserver(name: String) -> any Observer {
  LiveObserver(name: name, logger: NoopLogger(), tracer: NoopTracer())
}
