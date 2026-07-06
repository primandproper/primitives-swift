import ObservabilityLog
import Testing

@testable import Observability

@Suite("ObservabilityLog — swift-log interop")
struct SwiftLogLoggerTests {

  @Test("SwiftLogLogger conforms to the core Logger seam and is value-semantic")
  func conformsAndValueSemantic() {
    let base: any Logger = SwiftLogLogger(label: "test")
    // with* returns a fresh logger; the original is unchanged (mirrors the Logger contract).
    let named = base.withName("component").withValue("user.id", 42).withValue("flag", true)
    #expect(named is SwiftLogLogger)
    // Emitting must not crash (output goes to whatever LoggingSystem.bootstrap selected).
    base.info("hello")
    named.error("boom", SampleLogError())
  }

  @Test("can back a Pillars as the logger pillar")
  func backsPillars() async {
    let pillars = Pillars(
      logger: SwiftLogLogger(label: "app"), tracer: NoopTracer(), metrics: NoopMetricsProvider())
    #expect(pillars.logger is SwiftLogLogger)
    await pillars.shutdown()
  }
}

private struct SampleLogError: Error {}
