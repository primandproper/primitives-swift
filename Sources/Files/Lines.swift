/// Splits `bytes` into lines, ported from platform-go's `files.Lines`. See ``LineSequence`` for the
/// exact line-splitting semantics (blank lines preserved, unterminated final line yielded, no length
/// cap).
public func lines<Bytes: AsyncSequence & Sendable>(from bytes: Bytes) -> LineSequence<Bytes>
where Bytes.Element == UInt8 {
  LineSequence(bytes: bytes)
}

/// Groups `bytes`'s lines into chunks of up to `size`, ported from platform-go's `files.Chunks`.
///
/// - Throws: ``FilesError/nonPositiveChunkSize`` if `size` is not greater than zero. Go instead yields
///   the error once via the returned iterator on first iteration (`iter.Seq2` has no other way to signal
///   a construction-time failure); this port validates synchronously up front, the more natural Swift
///   shape for what is otherwise a plain constructor.
public func chunks<Bytes: AsyncSequence & Sendable>(
  from bytes: Bytes, size: Int
) throws -> ChunkSequence<LineSequence<Bytes>>
where Bytes.Element == UInt8 {
  guard size > 0 else { throw FilesError.nonPositiveChunkSize }
  return ChunkSequence(lines: LineSequence(bytes: bytes), size: size)
}

/// Returns up to `count` lines of `bytes` after skipping `offset` lines — "the 10 lines after the first
/// 8" is `sliceLines(from: bytes, offset: 8, count: 10)`. Reads no further than it needs to. Ported from
/// platform-go's `files.SliceLines`.
///
/// - Throws: ``FilesError/negativeOffset`` or ``FilesError/negativeCount`` for a negative argument, or
///   ``FilesError/offsetBeyondEOF`` if `offset` lands at or past the end of the input. A `count` of zero
///   returns an empty array without error, and without reading anything.
public func sliceLines<Bytes: AsyncSequence & Sendable>(
  from bytes: Bytes, offset: Int, count: Int
) async throws -> [String]
where Bytes.Element == UInt8 {
  try await sliceLinesOfLines(from: LineSequence(bytes: bytes), offset: offset, count: count)
}

/// The line-sequence-based core shared by `sliceLines(from:offset:count:)` (bytes) and
/// ``FileReader``'s file-backed windowed reads (which start from a ``FileLines`` rather than raw bytes,
/// so they can't route through the bytes-based overload above). Named distinctly from `sliceLines`
/// (rather than overloaded on `Lines.Element == String`) because a same-named call from inside
/// ``FileReader``'s own `sliceLines(atPath:offset:count:)` method would otherwise resolve to that
/// enclosing method itself rather than this free function.
func sliceLinesOfLines<Lines: AsyncSequence & Sendable>(
  from lines: Lines, offset: Int, count: Int
) async throws -> [String]
where Lines.Element == String {
  if offset < 0 { throw FilesError.negativeOffset }
  if count < 0 { throw FilesError.negativeCount }
  if count == 0 { return [] }

  var out: [String] = []
  out.reserveCapacity(count)
  var skipped = 0
  var reached = false

  for try await line in lines {
    if skipped < offset {
      skipped += 1
      continue
    }

    reached = true
    out.append(line)
    if out.count == count { break }
  }

  guard reached else { throw FilesError.offsetBeyondEOF }
  return out
}
