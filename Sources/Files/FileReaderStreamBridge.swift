/// Bridges a pull-based `AsyncSequence` (``FileLines``, ``ChunkSequence``) into the concrete
/// `AsyncThrowingStream` ``FileReader`` exposes at its seam boundary — see ``FileReader`` for why the
/// protocol can't just return the pull-based sequence type directly (an `any AsyncSequence<Element,
/// Error>` existential needs a newer OS than this port targets).
///
/// A background `Task` pumps `sequence` into the stream's continuation. Ending the stream — natural
/// completion, a thrown error, or the consumer stepping away — cancels the task via `onTermination`,
/// which propagates into `sequence`'s own iteration (``FileLines``/``ChunkSequence`` both check
/// cancellation cooperatively through their underlying `FileHandle.bytes` reads) so its resources (the
/// open file handle) are released the same way they would be if a caller iterated `sequence` directly.
func bridgeToThrowingStream<S: AsyncSequence & Sendable>(
  _ sequence: S
) -> AsyncThrowingStream<S.Element, Error>
where S.Element: Sendable {
  AsyncThrowingStream { continuation in
    let task = Task {
      do {
        for try await item in sequence {
          continuation.yield(item)
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }

    continuation.onTermination = { _ in task.cancel() }
  }
}
