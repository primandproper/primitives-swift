import Testing

@testable import CircuitBreaking

/// Unit coverage for ``RollingWindow`` — the fixed-size ring of time buckets the breaker trips on. The
/// breaker tests exercise it indirectly through the state machine; these pin its aging/eviction contract
/// directly, at the window boundaries where an off-by-one would silently keep or drop a sample.
@Suite("RollingWindow sample aging and eviction")
struct RollingWindowTests {
  @Test("totals sums every bucket inside the window ending at the current index")
  func totalsWithinWindow() {
    var window = RollingWindow(bucketCount: 3)
    window.recordFailure(at: 0)
    window.recordSuccess(at: 1)
    window.recordFailure(at: 2)

    // Window at index 2 is [0, 2] — all three buckets are live.
    let totals = window.totals(at: 2)
    #expect(totals.failures == 2)
    #expect(totals.successes == 1)
  }

  @Test("a bucket that has aged past the window boundary stops counting")
  func agedBucketEvicted() {
    var window = RollingWindow(bucketCount: 3)
    window.recordFailure(at: 0)
    window.recordFailure(at: 1)

    // At index 2 the window is [0, 2]: both failures are still in range.
    #expect(window.totals(at: 2).failures == 2)
    // At index 3 the window is [1, 3]: index 0 has just aged out.
    #expect(window.totals(at: 3).failures == 1)
    // At index 4 the window is [2, 4]: both original failures have aged out.
    #expect(window.totals(at: 4).failures == 0)
  }

  @Test("ring-slot reuse at the bucketCount wraparound clears the stale bucket instead of accumulating")
  func slotReuseClearsStaleBucket() {
    var window = RollingWindow(bucketCount: 3)
    window.recordFailure(at: 0)  // ring slot 0
    window.recordFailure(at: 0)  // slot 0 again -> two failures banked at index 0

    // Index 3 maps to the same ring slot (3 % 3 == 0). Writing there must reset the slot to index 3 and
    // discard index 0's two failures, not add to them — the lazy eviction in `slot(for:)`.
    window.recordSuccess(at: 3)

    let totals = window.totals(at: 3)  // window [1, 3]
    #expect(totals.failures == 0)
    #expect(totals.successes == 1)
  }

  @Test("reset clears every bucket")
  func resetClearsEverything() {
    var window = RollingWindow(bucketCount: 4)
    window.recordFailure(at: 0)
    window.recordSuccess(at: 1)
    window.recordFailure(at: 2)

    window.reset()

    let totals = window.totals(at: 2)
    #expect(totals.failures == 0)
    #expect(totals.successes == 0)
  }

  @Test("never-written buckets contribute nothing to the totals")
  func neverWrittenContributeNothing() {
    var window = RollingWindow(bucketCount: 5)
    window.recordFailure(at: 10)

    // Window [6, 10]: only index 10 has ever been written; the other four slots (index -1) don't count.
    let totals = window.totals(at: 10)
    #expect(totals.failures == 1)
    #expect(totals.successes == 0)
  }

  @Test("a single-bucket window retains only the current index")
  func singleBucketWindow() {
    var window = RollingWindow(bucketCount: 1)
    window.recordFailure(at: 0)
    #expect(window.totals(at: 0).failures == 1)

    // Advancing one index reuses the sole slot and evicts index 0.
    window.recordSuccess(at: 1)
    let totals = window.totals(at: 1)
    #expect(totals.failures == 0)
    #expect(totals.successes == 1)
  }
}
