/// Random element selection, ported from platform-go's `random/slices.go` (`Element[T]`).
///
/// Go returns the zero value of `T` for an empty slice rather than panicking. Swift generics have
/// no "zero value" concept, so the idiomatic equivalent is an `Optional` that is `nil` when the
/// collection is empty — which is exactly what the standard library's `Collection.randomElement()`
/// already gives you. This free function is a thin, faithful mirror of the Go name; new Swift code
/// can just call `randomElement()` directly.
///
/// Like Go's use of `math/rand` here, selection uses the default `SystemRandomNumberGenerator`;
/// this is a convenience picker, not a place that needs cryptographic randomness.
public func randomElement<C: Collection>(from collection: C) -> C.Element? {
  collection.randomElement()
}
