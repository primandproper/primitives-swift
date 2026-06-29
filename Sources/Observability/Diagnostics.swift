import Foundation

/// The iOS analogue of platform-go's `profiling.Provider`. There is no pprof/pyroscope on-device;
/// the equivalent is MetricKit, which delivers daily power/performance and crash diagnostics payloads.
/// Lifecycle mirrors Go: `start()` subscribes, `shutdown()` unsubscribes.
public protocol DiagnosticsProvider: Sendable {
  func start()
  func shutdown()
}

public struct NoopDiagnostics: DiagnosticsProvider {
  public init() {}
  public func start() {}
  public func shutdown() {}
}

#if canImport(MetricKit) && os(iOS)
  import MetricKit

  /// Subscribes to MetricKit and logs received payloads through a platform-swift ``Logger``. Minimal by
  /// design — a first cut that surfaces payloads; richer routing (export to a collector) can follow.
  public final class MetricKitDiagnostics: NSObject, DiagnosticsProvider, MXMetricManagerSubscriber,
    @unchecked Sendable
  {
    private let logger: any Logger

    public init(logger: any Logger) {
      self.logger = logger
      super.init()
    }

    public func start() {
      MXMetricManager.shared.add(self)
      logger.info("MetricKit diagnostics subscribed")
    }

    public func shutdown() {
      MXMetricManager.shared.remove(self)
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {
      for payload in payloads {
        logger.info("MetricKit metric payload: \(payload.jsonRepresentation().count) bytes")
      }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
      for payload in payloads {
        logger.info("MetricKit diagnostic payload: \(payload.jsonRepresentation().count) bytes")
      }
    }
  }
#endif
