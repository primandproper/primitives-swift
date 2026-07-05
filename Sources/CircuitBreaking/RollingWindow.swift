/// A fixed-size ring of time buckets counting recent failures and successes — the Swift port of the
/// rolling window that platform-go's breaker inherited from `rubyist/circuitbreaker` (its `window.go`).
///
/// The breaker trips on the error *rate over a recent window*, not on lifetime totals: a dependency that
/// failed a hundred times last hour but is healthy now should not stay tripped forever. Go got this
/// window from a third-party library; the Swift port has no external dependency, so it reimplements the
/// same idea directly — a ring of `bucketCount` buckets, each covering an equal slice of wall-window
/// time, summed to produce the current error rate.
///
/// This is a plain `struct` with `mutating` methods rather than its own synchronized type: it is only
/// ever touched from inside ``StandardCircuitBreaker``'s actor, which already serializes access, so
/// adding a second lock here would guard nothing. The caller supplies a monotonically non-decreasing
/// bucket index (derived from a ``ContinuousClock``); this type stays time-unit agnostic and just does
/// the bookkeeping.
struct RollingWindow {
  private struct Bucket {
    /// The absolute bucket index this slot currently holds, or `-1` when never written.
    var index: Int
    var failures: Int
    var successes: Int
  }

  private let bucketCount: Int
  private var buckets: [Bucket]

  init(bucketCount: Int) {
    self.bucketCount = max(1, bucketCount)
    self.buckets = Array(
      repeating: Bucket(index: -1, failures: 0, successes: 0), count: self.bucketCount)
  }

  /// Returns the ring slot for `index`, lazily clearing it when it still holds an older, now-expired
  /// index that has cycled around to reuse this slot.
  private mutating func slot(for index: Int) -> Int {
    let slot = index % bucketCount
    if buckets[slot].index != index {
      buckets[slot] = Bucket(index: index, failures: 0, successes: 0)
    }
    return slot
  }

  mutating func recordFailure(at index: Int) {
    buckets[slot(for: index)].failures += 1
  }

  mutating func recordSuccess(at index: Int) {
    buckets[slot(for: index)].successes += 1
  }

  /// Sums the buckets still inside the window ending at `currentIndex` — i.e. those whose absolute
  /// index falls within the most recent `bucketCount` slices. Older buckets, and never-written ones,
  /// contribute nothing.
  func totals(at currentIndex: Int) -> (failures: Int, successes: Int) {
    let lowerBound = currentIndex - bucketCount + 1
    var failures = 0
    var successes = 0
    for bucket in buckets where bucket.index >= lowerBound && bucket.index <= currentIndex {
      failures += bucket.failures
      successes += bucket.successes
    }
    return (failures, successes)
  }

  /// Clears every bucket, mirroring the library's `Reset()` — used when a half-open trial succeeds and
  /// the breaker closes, so a stale error rate can't immediately re-trip it.
  mutating func reset() {
    for i in buckets.indices {
      buckets[i] = Bucket(index: -1, failures: 0, successes: 0)
    }
  }
}
