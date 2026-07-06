import Foundation
import Observability

/// A **native**, brute-force ``VectorSearcher`` holding every vector in memory and scanning them all on
/// each query. The iOS-native replacement for Go's dropped pgvector and Qdrant backends (see ``Search``):
/// a phone's working set is thousands, not billions, of vectors, so a linear scan with SIMD-friendly
/// arithmetic is entirely adequate and needs no server or index structure.
///
/// An `actor` guards the record store (matching `Sources/Cache`'s `InMemoryCache`); observability threads
/// through an injected ``Observability/Pillars`` (SVC-10), each operation opening a span and emitting
/// `_requests`/`_errors` counters plus a `_latency_ms` histogram under ``metricName``.
///
/// The index is fixed to a ``dimensions`` width and a ``metric`` at construction — a vector whose length
/// differs is rejected with ``SearchError/dimensionMismatch(expected:actual:)``, and an empty vector with
/// ``SearchError/emptyEmbedding``, mirroring Go's `ErrDimensionMismatch`/`ErrEmptyEmbedding` sentinels.
public actor InMemoryVectorIndex: VectorSearcher {
  /// Default observability/metric prefix. Metrics emit as `in_memory_vector_search_requests` /
  /// `in_memory_vector_search_errors` / `in_memory_vector_search_latency_ms`.
  public static let defaultName = "in_memory_vector_search"

  /// The fixed vector width this index accepts. A caller sizing an ``Embeddings/Embedder`` can read the
  /// embedder's `dimensions` and pass it here.
  public nonisolated let dimensions: Int
  /// The scoring function used by ``query(_:)``.
  public nonisolated let metric: VectorDistanceMetric

  private var records: [String: VectorRecord] = [:]
  private let observer: any Observer
  private let metrics: any MetricsProvider
  private let metricName: String

  /// - Parameters:
  ///   - dimensions: the fixed vector width. Must be positive, else ``init`` throws
  ///     ``SearchError/invalidDimension(_:)`` (Go's `ErrInvalidDimension`).
  ///   - metric: the distance metric. Defaults to ``VectorDistanceMetric/cosine``, the PORT-08 default.
  ///   - name: observability/metric prefix. Defaults to ``defaultName``.
  ///   - pillars: observability pillars; side effects open spans/metrics through these. Defaults to
  ///     ``Observability/Pillars/noop``.
  public init(
    dimensions: Int,
    metric: VectorDistanceMetric = .cosine,
    name: String = InMemoryVectorIndex.defaultName,
    pillars: Pillars = .noop
  ) throws {
    guard dimensions > 0 else { throw SearchError.invalidDimension(dimensions) }
    self.dimensions = dimensions
    self.metric = metric
    self.metricName = name
    self.observer = LiveObserver(name: name, logger: pillars.logger, tracer: pillars.tracer)
    self.metrics = pillars.metrics
  }

  public func upsert(_ records: [VectorRecord]) async throws {
    let op = observer.begin("vector.upsert")
    op.set("vector.count", records.count)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    do {
      for record in records {
        try validate(record.embedding)
        self.records[record.id] = record
      }
      metrics.counter("\(metricName)_requests").increment()
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "vector upsert failed")
      throw error
    }
  }

  public func delete(ids: [String]) async throws {
    let op = observer.begin("vector.delete")
    op.set("vector.count", ids.count)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    for id in ids { records[id] = nil }
    metrics.counter("\(metricName)_requests").increment()
  }

  public func wipe() async throws {
    let op = observer.begin("vector.wipe")
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    records.removeAll()
    metrics.counter("\(metricName)_requests").increment()
  }

  public func query(_ request: VectorQuery) async throws -> [VectorSearchResult] {
    let op = observer.begin("vector.query")
    op.set("vector.topK", request.topK)
    let start = ContinuousClock.now
    defer {
      recordLatency(since: start)
      op.end()
    }

    do {
      try validate(request.embedding)

      // Score every record, then sort most-similar-first. `score` is defined higher-is-better for all
      // metrics (euclidean is negated), so a single descending sort covers all three.
      var scored: [VectorSearchResult] = records.values.map { record in
        VectorSearchResult(
          id: record.id,
          score: Self.score(request.embedding, record.embedding, metric: metric),
          metadata: record.metadata)
      }
      scored.sort { $0.score > $1.score }

      let limited = request.topK > 0 ? Array(scored.prefix(request.topK)) : scored
      metrics.counter("\(metricName)_requests").increment()
      op.set("vector.results", limited.count)
      return limited
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "vector query failed")
      throw error
    }
  }

  /// Test/inspection seam: the number of records currently held.
  public var count: Int { records.count }

  // MARK: - Internals

  private func validate(_ embedding: [Float]) throws {
    guard !embedding.isEmpty else { throw SearchError.emptyEmbedding }
    guard embedding.count == dimensions else {
      throw SearchError.dimensionMismatch(expected: dimensions, actual: embedding.count)
    }
  }

  private func recordLatency(since start: ContinuousClock.Instant) {
    metrics.histogram("\(metricName)_latency_ms").record(start.duration(to: .now).millisecondsValue)
  }

  /// The scoring functions. `a` and `b` are guaranteed equal, non-zero length by the callers' ``validate``.
  /// Every metric returns higher-is-better (euclidean is negated) so ``query(_:)`` sorts uniformly.
  static func score(_ a: [Float], _ b: [Float], metric: VectorDistanceMetric) -> Float {
    switch metric {
    case .cosine:
      let denominator = magnitude(a) * magnitude(b)
      return denominator == 0 ? 0 : dot(a, b) / denominator
    case .dot:
      return dot(a, b)
    case .euclidean:
      var sum: Float = 0
      for i in 0..<a.count {
        let d = a[i] - b[i]
        sum += d * d
      }
      return -sum.squareRoot()
    }
  }

  static func dot(_ a: [Float], _ b: [Float]) -> Float {
    var sum: Float = 0
    for i in 0..<a.count { sum += a[i] * b[i] }
    return sum
  }

  static func magnitude(_ a: [Float]) -> Float {
    dot(a, a).squareRoot()
  }
}
