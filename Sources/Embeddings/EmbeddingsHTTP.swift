import DurationWire
import Foundation
import HTTPClient
import Observability

/// The error-body shape OpenAI returns on a non-2xx: `{"error":{"message":…}}` — decoding `error.message`
/// mirrors `Sources/LLM`'s `WireErrorBody`.
struct EmbeddingsWireErrorBody: Decodable {
  struct Inner: Decodable { let message: String? }
  let error: Inner?
}

/// Builds the `URLSession` an ``Embedder`` HTTP backend makes its calls through, the analogue of
/// `Sources/LLM`'s `makeLLMSession`. A `.zero` timeout means a 120s default; the resource timeout is
/// scaled 3× like `HTTPClientConfig` does.
func makeEmbeddingsSession(timeout: Duration) -> URLSession {
  let effective = timeout > .zero ? timeout : .seconds(120)
  let config = URLSessionConfiguration.default
  config.timeoutIntervalForRequest = effective.timeInterval
  config.timeoutIntervalForResource = (effective * 3).timeInterval
  return URLSession(configuration: config)
}

/// The shared instrumented-embed wrapper ``OpenAIEmbedder`` runs its transport through — the analogue of
/// `Sources/LLM`'s `runInstrumentedCompletion`. Opens an ``Observability/Observer`` operation, records
/// `embeddings.model`/`embeddings.input.length` on the way in and the resolved vector's dimensionality on
/// the way out, always emits the `_latency_ms` histogram, and increments the `_requests`/`_errors`
/// counters — the same metric-naming convention `runInstrumentedCompletion` uses, renamed to this
/// module's `metricName`.
///
/// Error handling mirrors `Sources/LLM`'s wrapper: a typed ``EmbeddingsError`` (the classified provider
/// failure, or a translated `HTTPClientError.circuitBroken`) is recorded and rethrown **raw** so callers
/// can `catch EmbeddingsError.rateLimit(let retryAfter)`; cancellation propagates raw so a retry wrapper
/// sees it as terminal; any other unexpected error is wrapped with `op.error` for context.
func runInstrumentedEmbed(
  text: String,
  model: String,
  observer: any Observer,
  metrics: any MetricsProvider,
  metricName: String,
  transport: (_ model: String) async throws -> [Float]
) async throws -> [Float] {
  try await observer.operation(name: "Embed") { op in
    op.set("embeddings.model", model).set("embeddings.input.length", text.count)

    let start = DispatchTime.now()
    defer {
      let elapsedNanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
      metrics.histogram("\(metricName)_latency_ms").record(Double(elapsedNanos) / 1_000_000)
    }

    do {
      let vector = try await transport(model)
      metrics.counter("\(metricName)_requests").increment()
      op.set("embeddings.dimensions", vector.count)
      return vector
    } catch let error as HTTPClientError {
      metrics.counter("\(metricName)_errors").increment()
      let mapped: EmbeddingsError =
        error == .circuitBroken
        ? .circuitBroken
        : .provider(
          status: 0, message: error.description)
      op.acknowledge(mapped, "embedding request")
      throw mapped
    } catch let error as EmbeddingsError {
      metrics.counter("\(metricName)_errors").increment()
      op.acknowledge(error, "embedding request")
      throw error
    } catch {
      metrics.counter("\(metricName)_errors").increment()
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        op.acknowledge(error, "embedding request cancelled")
        throw error
      }
      throw op.error(error, "embedding request failed")
    }
  }
}
