import Foundation
import os

/// A lock-backed fan-out for ``DeviceToken`` values, shared by ``SystemNotificationCenterManager`` and
/// ``MockNotificationCenterManager`` so the ``NotificationCenterManager/deviceTokens()`` /
/// ``NotificationCenterManager/receiveDeviceToken(_:)`` machinery isn't written twice.
///
/// `deviceTokens()` is a *synchronous* protocol requirement, so on an `actor` conformer it must be
/// `nonisolated` and can't touch actor state; this helper keeps the continuation registry behind an
/// `OSAllocatedUnfairLock` instead — the same nonisolated-lock shape ``Observability``'s recorders and
/// `Capitalism`'s `PurchaseManagerMock` use. A `final class` (not a struct) because every ``stream()``
/// and ``broadcast(_:)`` call must see the one shared registry.
final class DeviceTokenBroadcaster: Sendable {
  private struct State {
    var nextID = 0
    var continuations: [Int: AsyncStream<DeviceToken>.Continuation] = [:]
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// A fresh stream registered with this broadcaster. Every ``broadcast(_:)`` after iteration begins is
  /// delivered to it; it deregisters itself when its consuming task is cancelled.
  func stream() -> AsyncStream<DeviceToken> {
    AsyncStream { continuation in
      let id = state.withLock { s -> Int in
        let id = s.nextID
        s.nextID += 1
        s.continuations[id] = continuation
        return id
      }
      continuation.onTermination = { [state] _ in
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
      }
    }
  }

  /// Yields `token` to every currently-registered stream.
  func broadcast(_ token: DeviceToken) {
    // Snapshot under the lock, then yield outside it: `yield` shouldn't run while holding the lock.
    let continuations = state.withLock { Array($0.continuations.values) }
    for continuation in continuations { continuation.yield(token) }
  }
}
