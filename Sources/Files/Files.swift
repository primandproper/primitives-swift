/// # Files
///
/// Ported from platform-go's `files` package (`files.go`, `lines.go`, `lines_file.go`, `stream.go`,
/// `decode.go`, `dir.go`) — ergonomic helpers for reading text files: iterating line by line or in
/// fixed-size chunks, slicing a window of lines, and decoding a structured file into a typed value via
/// ``Encoding``.
///
/// What travels over, reshaped for Swift:
///   * ``LineSequence`` / ``ChunkSequence`` / ``FileLines`` — `AsyncSequence`-based line and chunk
///     readers, ported from Go's `Lines`/`Chunks`/`LinesFile`/`ChunksFile`. Go exposes two shapes of
///     chunked reading — a pull-driven `iter.Seq2` (`ChunksFile`) and a background-goroutine channel
///     (`StreamChunksFile`) — because `iter.Seq2` can't itself express asynchronous production. Swift's
///     `AsyncSequence` already unifies both: iteration is cooperatively pull-driven regardless of how
///     the producer works, so this port has exactly one chunked-reading shape.
///   * `sliceLines(from:offset:count:)` / ``FileReader/sliceLines(atPath:offset:count:)`` — windowed
///     reads, ported from Go's `SliceLines`/`SliceLinesFile`.
///   * `decode(_:from:contentType:)` / `decodeFile(_:atPath:contentType:)` — the typed decode helper,
///     ported from Go's generic `Decode[T]`/`DecodeFile[T]`, built on ``Encoding``'s `ClientEncoder`
///     rather than re-threading Go's observability-aware one-off encoder construction.
///   * ``FileReader`` / ``LiveFileReader`` / ``NoopFileReader`` / ``FileReaderMock`` — the seam
///     protocol and its conformers. Go's `files` package has no such indirection (every caller uses the
///     package-level functions against a package-private `defaultReader`); this port adds the seam
///     because every protocol-bearing module in this port ships one (Noop + Mock), and because a
///     sandboxed ``Dir`` needs *something* injectable to open files through.
///   * ``Dir`` / ``DirRoot`` — a sandbox-rooted directory handle, ported from Go's `Dir`/`OpenDir`/
///     `NewDir`. This is the one place the port **deliberately diverges in behavior**, not just shape:
///     Go's `Dir.Chdir`/`Dir.Sub` navigate freely to any ancestor or sibling directory (see
///     `dir_test.go`'s "Chdir navigates to the parent directory"). On iOS, a `Dir` is rooted at the
///     app's actual sandbox boundary — its documents directory or an app-group container — so letting
///     it navigate to an arbitrary parent would defeat the sandbox rather than just being a
///     directory-listing convenience. This port's ``Dir`` resolves names against a fixed root and
///     rejects anything (`..`, an absolute override, a symlink) that would escape it; there is no
///     mutating `Chdir` at all, and ``Dir/sub(_:)`` can only descend, never escape.
///
/// Dropped entirely:
///   * The `Observer`/logger/tracer-provider threading Go's `standardReader` and `Dir` carry
///     (`NewReader(logger, tracerProvider)`, `NewDir(path, logger, tracerProvider)`). This module has no
///     dependency on `Observability` (see the port task); a caller that wants a span around a read
///     wraps the call at its own layer, the same way ``Encoding``'s `ClientEncoder` dropped `context`.
///   * `MustLinesFile`/`MustChunksFile`/`MustAllLines`/`MustSliceLines`/`MustDecode`/`MustDecodeFile` —
///     Go's panic-on-error convenience wrappers. Swift's `try!` already covers the same need at the call
///     site without a parallel API surface.
///   * `AllLines`/`AllChunks` — Go conveniences for materializing an entire small input. Any caller can
///     write `try await someSequence.reduce(into: []) { $0.append($1) }` (or a plain `for try await`
///     loop); porting a named wrapper for that one line didn't earn its keep.
public enum Files {}
