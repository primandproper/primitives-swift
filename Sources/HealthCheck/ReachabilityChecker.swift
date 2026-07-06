import Network
import os

/// A ``Checker`` reporting whether the device currently has a usable network path, backed by Apple's
/// `Network` framework `NWPathMonitor`. Go's `healthcheck` package has no reachability checker of its own —
/// server-side Go has no concept of "is *this* device online," only whether a specific downstream dependency
/// answers — so this is new surface for the iOS port, filling the "reachability" item called out in
/// `PORTING.md`'s Wave 5 plan.
///
/// **Why a fresh monitor per check, not one long-lived instance.** `NWPathMonitor` is designed to be
/// started once and observed for the app's lifetime via `pathUpdateHandler`, but ``Checker/check()`` is a
/// pull-based, one-shot API called repeatedly by ``HealthCheckRegistry``. Spinning up a monitor, taking its
/// first reported path, and cancelling it keeps this checker stateless and `Sendable` as a plain `struct`
/// (no actor needed to guard a long-lived monitor instance) at the cost of a small per-check setup — cheap
/// relative to ``HealthCheckRegistry/defaultCheckTimeout``.
public struct ReachabilityChecker: Checker {
  public let name: String
  private let requiredInterfaceType: NWInterface.InterfaceType?

  /// - Parameters:
  ///   - name: Identifies this component in ``HealthCheckResult/components``.
  ///   - requiredInterfaceType: Restricts the monitored path to a specific interface (e.g. `.wifi`,
  ///     `.cellular`), mirroring `NWPathMonitor(requiredInterfaceType:)`. `nil` (the default) monitors any
  ///     interface, matching plain `NWPathMonitor()`.
  public init(
    name: String = "reachability", requiredInterfaceType: NWInterface.InterfaceType? = nil
  ) {
    self.name = name
    self.requiredInterfaceType = requiredInterfaceType
  }

  public func check() async throws {
    let status = await currentPathStatus()
    guard status == .satisfied else {
      throw HealthCheckError.unreachable(String(describing: status))
    }
  }

  /// Starts a fresh monitor, resumes with its first reported path status, and cancels it. Guards against
  /// `pathUpdateHandler` firing more than once before cancellation takes effect with a lock-protected flag,
  /// since `NWPathMonitor` offers no "give me exactly one update" API.
  private func currentPathStatus() async -> NWPath.Status {
    let monitor =
      requiredInterfaceType.map(NWPathMonitor.init(requiredInterfaceType:)) ?? NWPathMonitor()
    let queue = DispatchQueue(label: "healthcheck.reachability-checker")
    return await withCheckedContinuation {
      (continuation: CheckedContinuation<NWPath.Status, Never>) in
      let resumed = OSAllocatedUnfairLock(initialState: false)
      monitor.pathUpdateHandler = { path in
        let shouldResume = resumed.withLock { alreadyResumed in
          guard !alreadyResumed else { return false }
          alreadyResumed = true
          return true
        }
        guard shouldResume else { return }
        continuation.resume(returning: path.status)
        monitor.cancel()
      }
      monitor.start(queue: queue)
    }
  }
}
