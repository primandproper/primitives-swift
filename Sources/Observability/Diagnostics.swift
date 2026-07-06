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

// MARK: - Payload value types (platform-independent, always compiled)

/// A decoded crash report distilled from `MXCrashDiagnostic`. Only the fields that identify the
/// crash are surfaced; the raw call-stack tree is intentionally omitted here (it is large and better
/// exported wholesale by a richer sink). Sendable so it can cross isolation boundaries to a consumer.
public struct CrashDiagnostic: Sendable, Equatable {
  public var terminationReason: String?
  public var exceptionType: Int?
  public var exceptionCode: Int?
  public var signal: Int?
  public var virtualMemoryRegionInfo: String?

  public init(
    terminationReason: String? = nil,
    exceptionType: Int? = nil,
    exceptionCode: Int? = nil,
    signal: Int? = nil,
    virtualMemoryRegionInfo: String? = nil
  ) {
    self.terminationReason = terminationReason
    self.exceptionType = exceptionType
    self.exceptionCode = exceptionCode
    self.signal = signal
    self.virtualMemoryRegionInfo = virtualMemoryRegionInfo
  }
}

/// A decoded hang report distilled from `MXHangDiagnostic`.
public struct HangDiagnostic: Sendable, Equatable {
  /// The measured hang duration in seconds.
  public var durationSeconds: Double

  public init(durationSeconds: Double) {
    self.durationSeconds = durationSeconds
  }
}

/// A Sendable snapshot of the crash/hang information from a single `MXDiagnosticPayload`, surfaced to
/// a consumer via ``DiagnosticPayloadHandler``.
public struct DiagnosticPayload: Sendable, Equatable {
  public var crashes: [CrashDiagnostic]
  public var hangs: [HangDiagnostic]

  public init(crashes: [CrashDiagnostic] = [], hangs: [HangDiagnostic] = []) {
    self.crashes = crashes
    self.hangs = hangs
  }

  public var isEmpty: Bool { crashes.isEmpty && hangs.isEmpty }
}

/// The seam the caller supplies to receive decoded diagnostics rather than only having them logged.
/// `@Sendable` because MetricKit invokes delivery off the main actor and the handler may hop
/// isolation domains.
public typealias DiagnosticPayloadHandler = @Sendable (DiagnosticPayload) -> Void

/// Anything that can be reduced to a ``DiagnosticPayload``. `MXDiagnosticPayload` conforms under the
/// MetricKit gate; tests conform a fake so the decode/dispatch layer is exercisable headless.
public protocol DiagnosticPayloadConvertible {
  func asDiagnosticPayload() -> DiagnosticPayload
}

extension DiagnosticPayload: DiagnosticPayloadConvertible {
  public func asDiagnosticPayload() -> DiagnosticPayload { self }
}

/// The platform-independent decode + fan-out core shared by ``MetricKitDiagnostics``. Pulled out of
/// the MetricKit gate so the logging + handler dispatch is unit-testable on any host.
struct DiagnosticsDispatcher {
  let logger: any Logger
  let handler: DiagnosticPayloadHandler?

  func dispatch<P: DiagnosticPayloadConvertible>(_ payloads: [P]) {
    for source in payloads {
      let payload = source.asDiagnosticPayload()
      logger.info(
        "MetricKit diagnostic payload: crashes=\(payload.crashes.count) hangs=\(payload.hangs.count)")
      handler?(payload)
    }
  }
}

#if canImport(MetricKit) && (os(iOS) || os(macOS))
  import MetricKit

  /// Subscribes to MetricKit and surfaces received payloads through a platform-swift ``Logger`` and,
  /// optionally, a ``DiagnosticPayloadHandler``. `MXMetricManager` delivers metrics only on iOS but
  /// delivers crash/hang diagnostics on both iOS and macOS 13+, hence the widened gate.
  public final class MetricKitDiagnostics: NSObject, DiagnosticsProvider, MXMetricManagerSubscriber,
    @unchecked Sendable
  {
    private let logger: any Logger
    private let dispatcher: DiagnosticsDispatcher

    /// - Parameters:
    ///   - logger: sink for lifecycle + summary lines.
    ///   - onDiagnostics: optional handler that receives decoded crash/hang payloads. When nil, the
    ///     provider only logs a summary — matching the original byte-count behaviour but structured.
    public init(logger: any Logger, onDiagnostics: DiagnosticPayloadHandler? = nil) {
      self.logger = logger
      self.dispatcher = DiagnosticsDispatcher(logger: logger, handler: onDiagnostics)
      super.init()
    }

    public func start() {
      MXMetricManager.shared.add(self)
      logger.info("MetricKit diagnostics subscribed")
    }

    public func shutdown() {
      MXMetricManager.shared.remove(self)
    }

    #if os(iOS)
      public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
          logger.info("MetricKit metric payload: \(payload.jsonRepresentation().count) bytes")
        }
      }
    #endif

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
      dispatcher.dispatch(payloads)
    }
  }

  extension MXDiagnosticPayload: DiagnosticPayloadConvertible {
    public func asDiagnosticPayload() -> DiagnosticPayload {
      DiagnosticPayload(
        crashes: (crashDiagnostics ?? []).map { crash in
          CrashDiagnostic(
            terminationReason: crash.terminationReason,
            exceptionType: crash.exceptionType?.intValue,
            exceptionCode: crash.exceptionCode?.intValue,
            signal: crash.signal?.intValue,
            virtualMemoryRegionInfo: crash.virtualMemoryRegionInfo)
        },
        hangs: (hangDiagnostics ?? []).map { hang in
          HangDiagnostic(
            durationSeconds: hang.hangDuration.converted(to: .seconds).value)
        })
    }
  }
#endif
