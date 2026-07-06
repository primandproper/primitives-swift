/// A small, fast, splitmix64-based deterministic random generator backing ``SeededFakeSource``.
///
/// Not cryptographically secure — reproducibility, not secrecy, is the point: the same seed always
/// produces the same sequence, which is what makes ``FakeGenerator`` useful as SwiftUI preview
/// data (stable snapshots) and in tests that assert reproducibility. Callers who need a CSPRNG
/// should reach for `RandomKit.StandardGenerator` instead.
struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
