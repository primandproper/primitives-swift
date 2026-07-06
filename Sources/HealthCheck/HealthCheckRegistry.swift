import Foundation
import Observability

/// Holds ``Checker``s and runs them, ported from platform-go's `healthcheck.registry`
/// (`healthcheck.go`).
///
/// **Concurrency shape.** Go guarded `[]Checker` with a `sync.RWMutex` and ran each check on its own
/// goroutine under `sync.WaitGroup`. The faithful, race-free Swift shape is an `actor` for the mutable
/// checker list — `register(_:)` and reading a snapshot for `checkAll()` are both actor-isolated, so no
/// explicit lock is needed — with the concurrent fan-out itself expressed as a `TaskGroup`
/// (``checkAll()``), Swift's structured-concurrency analogue of `WaitGroup` + goroutines.
///
/// **Per-check timeout.** Go derived each check's context via `context.WithTimeout(ctx,
/// defaultCheckTimeout)`, which only bounds a checker that itself honors `ctx.Done()`. This port makes the
/// timeout a hard race instead: each check runs in a nested `TaskGroup` against a `Task.sleep` sibling, and
/// whichever finishes first — the check or the clock — decides the outcome (see the private `run(_:)`
/// helper). A checker that ignores `Task` cancellation still gets classified ``Status/down`` promptly by
/// the timeout branch; only the actor's overall `checkAll()` return has to wait for it to actually unwind,
/// the same residual caveat Go's design carried.
///
/// **Observability.** Ported per this port's settled convention (see `PORTING.md`) rather than from any Go
/// counterpart — the Go package has none. Each check runs inside its own ``Observability/Operation`` (named
/// for the checker), and the overall `checkAll()` call runs inside one more, recording the checker count and
/// aggregate status.
public actor HealthCheckRegistry {
  /// Bounds each individual health check so one slow/hung component can't stall the whole probe endpoint,
  /// mirroring Go's `defaultCheckTimeout = 5 * time.Second`.
  public static let defaultCheckTimeout: Duration = .seconds(5)

  /// Observability name, feeding the observer's logger name and span names.
  public static let o11yName = "healthcheck_registry"

  private var checkers: [any Checker] = []
  private let checkTimeout: Duration
  private let observer: any Observer

  /// Primary initializer — inject an already-built observer (the test seam).
  public init(
    checkTimeout: Duration = HealthCheckRegistry.defaultCheckTimeout, observer: any Observer
  ) {
    self.checkTimeout = checkTimeout
    self.observer = observer
  }

  /// Convenience initializer building a production observer from bootstrapped pillars, the analogue of a
  /// Go call site handing `NewRegistry()` an already-wired `observability.Observer`.
  public init(checkTimeout: Duration = HealthCheckRegistry.defaultCheckTimeout, pillars: Pillars) {
    self.init(
      checkTimeout: checkTimeout, observer: makeObserver(HealthCheckRegistry.o11yName, pillars))
  }

  /// Adds a checker to the registry. Ported from Go's `Register`.
  ///
  /// Go's `Register` silently ignores a `nil` checker; Swift's non-optional `any Checker` parameter makes
  /// that case unrepresentable, so there is nothing to guard here.
  public func register(_ checker: any Checker) {
    checkers.append(checker)
  }

  /// Runs all registered checkers concurrently, each under its own timeout, and returns the aggregate
  /// result. Ported from Go's `CheckAll`.
  ///
  /// Overall ``Status`` is ``Status/up`` unless at least one component reports ``Status/down`` — identical
  /// to Go's `if o.res.Status == StatusDown { result.Status = StatusDown }` fold. An empty registry (no
  /// checkers registered) reports ``Status/up`` with no components, matching Go's zero-value result.
  public func checkAll() async -> HealthCheckResult {
    let op = observer.begin("checkAll")
    defer { op.end() }

    let snapshot = checkers
    op.set("healthcheck.checker_count", snapshot.count)

    let timeout = checkTimeout
    let observer = self.observer

    var components: [String: ComponentResult] = [:]
    await withTaskGroup(of: (String, ComponentResult).self) { group in
      for checker in snapshot {
        group.addTask {
          (checker.name, await Self.run(checker, timeout: timeout, observer: observer))
        }
      }
      for await (name, result) in group {
        components[name] = result
      }
    }

    let overall: Status = components.values.contains { $0.status == .down } ? .down : .up
    op.set("healthcheck.status", overall.rawValue)
    return HealthCheckResult(status: overall, components: components)
  }

  /// Runs a single checker, racing it against `timeout`. Whichever finishes first — the check or the
  /// clock — decides the ``ComponentResult``; the loser is cancelled via `group.cancelAll()` (see the
  /// type-level doc for the caveat on checkers that ignore cancellation).
  private static func run(
    _ checker: any Checker, timeout: Duration, observer: any Observer
  ) async -> ComponentResult {
    await observer.operation(checker.name) { op in
      do {
        try await withThrowingTaskGroup(of: Void.self) { group in
          group.addTask { try await checker.check() }
          group.addTask {
            try await Task.sleep(for: timeout)
            throw HealthCheckError.timedOut(check: checker.name)
          }
          try await group.next()
          group.cancelAll()
        }
        op.set("healthcheck.check_status", Status.up.rawValue)
        return ComponentResult(status: .up)
      } catch {
        op.acknowledge(error, "health check failed")
        return ComponentResult(status: .down, message: message(for: error))
      }
    }
  }

  /// The best human-readable string available for `error`, the analogue of Go's `err.Error()`.
  private static func message(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    return String(describing: error)
  }
}
