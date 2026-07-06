/// Converts a `Duration` (as returned by `ContinuousClock`) to whole-and-fractional milliseconds, for the
/// `_latency_ms` histograms. Kept module-private and uniquely named so importing `Cache` (which has its
/// own internal `timeIntervalValue`) alongside `Search` never raises an ambiguity.
extension Duration {
  var millisecondsValue: Double {
    let (seconds, attoseconds) = components
    // attoseconds are 1e-18 s; ×1e3 for ms → ÷1e15.
    return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
  }
}
