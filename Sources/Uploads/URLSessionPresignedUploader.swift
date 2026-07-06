import CircuitBreaking
import Foundation
import Observability

/// A **live** ``PresignedUploader`` that PUTs/POSTs object bytes to a pre-signed URL with `URLSession`.
///
/// It performs the upload with `URLSession.upload(for:from:)` — the same code path a `URLProtocol` stub
/// can intercept, so tests drive it hermetically with no network. The request is gated by an injected
/// ``CircuitBreaking/CircuitBreaker`` (defaulting to a ``CircuitBreaking/NoopCircuitBreaker`` that never
/// trips): an open breaker fails fast with ``UploadsError/circuitBroken`` before a doomed request leaves
/// the device, and each attempt records success/failure so repeated store faults trip it — the same
/// breaker contract ``HTTPClient`` uses. Telemetry rides an ``Observability/Observer`` operation.
///
/// **Background-upload shaping.** The default session is a foreground `URLSession`, which is all a
/// `URLProtocol`-stubbed test (and most in-app uploads of a small blob) needs. For uploads that must
/// survive app suspension, ``backgroundConfiguration(identifier:)`` builds a `background` configuration a
/// native adapter can drive via delegate callbacks with a *file* body — the async `upload(for:from:)` used
/// here is a foreground API, so that adapter is the deliberate wrap point, not this default impl.
public struct URLSessionPresignedUploader: PresignedUploader {
  /// Observability name for this component, feeding the observer's logger/span names.
  public static let o11yName = "uploads_presigned"

  private let session: URLSession
  private let observer: any Observer
  private let circuitBreaker: any CircuitBreaker

  /// Primary initializer — inject an already-built session, observer, and breaker. The seam tests use:
  /// pass a `URLSession` backed by a `URLProtocol` stub and a ``Observability/RecordingObserver`` to
  /// exercise the uploader hermetically.
  public init(
    session: URLSession,
    observer: any Observer,
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker()
  ) {
    self.session = session
    self.observer = observer
    self.circuitBreaker = circuitBreaker
  }

  /// Convenience initializer building the observer from pillars and the breaker from `circuitBreaker`
  /// config — the analogue of Go's `NewUploadManager(...)` for a remote provider. Uses a foreground
  /// ephemeral `URLSession` by default; pass a `session` to supply your own (e.g. a background one wrapped
  /// by a native adapter).
  public init(
    circuitBreaker circuitBreakerConfig: CircuitBreakerConfig,
    pillars: Pillars,
    session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.init(
      session: session,
      observer: LiveObserver(
        name: Self.o11yName, logger: pillars.logger, tracer: pillars.tracer),
      circuitBreaker: circuitBreakerConfig.provideCircuitBreaker(
        logger: pillars.logger, metrics: pillars.metrics))
  }

  /// A `URLSessionConfiguration` shaped for genuine background upload: uploads keep running after the app
  /// is suspended and the system relaunches the app to deliver completion. A native adapter drives it via
  /// a delegate and a file body (the async `upload(for:from:)` this default impl uses is foreground-only);
  /// exposed so callers can construct that adapter without re-deriving the settings.
  public static func backgroundConfiguration(identifier: String) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.allowsCellularAccess = true
    return configuration
  }

  @discardableResult
  public func upload(_ request: PresignedUploadRequest) async throws -> PresignedUploadResponse {
    try await observer.operation(name: "uploads.presigned.upload") { op in
      op.set("upload.method", request.method.rawValue)
      op.set("upload.url", request.url.absoluteString)
      op.set("upload.bytes", request.body.count)

      // Gate on the breaker before touching the network. Throw the typed sentinel raw so callers can
      // `catch UploadsError.circuitBroken` the way Go compares against `ErrCircuitBroken`.
      if await circuitBreaker.cannotProceed() {
        op.acknowledge(UploadsError.circuitBroken, "circuit breaker open; refusing upload")
        throw UploadsError.circuitBroken
      }

      var urlRequest = URLRequest(url: request.url)
      urlRequest.httpMethod = request.method.rawValue
      if let contentType = request.contentType, !contentType.isEmpty {
        urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
      }
      if let cacheControl = request.cacheControl, !cacheControl.isEmpty {
        urlRequest.setValue(cacheControl, forHTTPHeaderField: "Cache-Control")
      }
      for (name, value) in request.extraHeaders {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }

      do {
        // `upload(for:from:)` sends the body as the request payload — the `URLSessionUploadTask` path,
        // interceptable by a `URLProtocol` stub. The body is passed here rather than set on
        // `httpBody` so an upload task (not a data task) carries it.
        let (data, response) = try await session.upload(for: urlRequest, from: request.body)

        guard let http = response as? HTTPURLResponse else {
          await circuitBreaker.recordFailure()
          op.acknowledge(UploadsError.nonHTTPResponse, "upload response was not HTTP")
          throw UploadsError.nonHTTPResponse
        }

        op.set("upload.status", http.statusCode)

        guard (200..<300).contains(http.statusCode) else {
          // A non-2xx is a real store rejection (bad signature, expired URL, quota) — count it against the
          // breaker and surface it typed, unlike ``HTTPClient`` where a non-2xx is still a returned
          // response. A one-shot upload has no "partial success".
          await circuitBreaker.recordFailure()
          let message = Self.shortMessage(from: data)
          let failure = UploadsError.uploadFailed(status: http.statusCode, message: message)
          op.acknowledge(failure, "presigned upload rejected")
          throw failure
        }

        await circuitBreaker.recordSuccess()
        return PresignedUploadResponse(
          statusCode: http.statusCode,
          etag: Self.unquotedETag(http.value(forHTTPHeaderField: "ETag")),
          headers: Self.stringHeaders(http.allHeaderFields))
      } catch let error as UploadsError {
        throw error
      } catch {
        // A cancelled task is the caller abandoning the work, not a store fault: rethrow without counting
        // it against the breaker (consistent with ``HTTPClient`` / ``CircuitBreaking``).
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
          op.acknowledge(error, "presigned upload cancelled")
          throw error
        }
        await circuitBreaker.recordFailure()
        throw op.error(error, "presigned upload failed")
      }
    }
  }

  // MARK: - Response helpers

  /// A short, log-safe message from a (possibly large/binary) error body: the first 512 UTF-8-decodable
  /// bytes, trimmed.
  private static func shortMessage(from data: Data) -> String {
    guard !data.isEmpty else { return "" }
    let slice = data.prefix(512)
    let text = String(decoding: slice, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return text
  }

  /// Strips the surrounding quotes S3-family stores wrap around `ETag` values.
  private static func unquotedETag(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    var value = raw
    if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
      value = String(value.dropFirst().dropLast())
    }
    return value
  }

  /// Collapses `allHeaderFields` (`[AnyHashable: Any]`) to `[String: String]`, dropping non-string entries.
  private static func stringHeaders(_ fields: [AnyHashable: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in fields {
      if let name = key as? String, let stringValue = value as? String {
        out[name] = stringValue
      }
    }
    return out
  }
}
