import Observability

// Phase 5 (per the plan): OpenTelemetry-swift adapters that conform to the core protocols
// (`Logger`, `Tracer`/`Span`, `MetricsProvider`) plus W3C traceparent inject/extract for outbound
// URLSession requests, exposed as an `OTelPillars.make(...)` builder selectable via config.
//
// Deliberately not yet wired to the opentelemetry-swift dependency: keeping it out of Package.swift
// for now means the core graph resolves with no heavy transitive deps. Adding the dependency and the
// adapters is a self-contained follow-up that does not touch the core target.
//
// Sketch of the intended surface:
//
//   public enum OTelPillars {
//       public static func make(serviceName: String, endpoint: URL, headers: [String: String] = [:]) -> Pillars
//   }
//
//   struct OTelLogger: Logger { /* bridges to OTel logs */ }
//   struct OTelTracer: Tracer { /* spans link via SpanContextStore.current; export over OTLP */ }
//   struct OTelMetricsProvider: MetricsProvider { /* bootstraps an OTel MetricsFactory */ }
//   enum W3CPropagation { /* inject/extract `traceparent` on URLRequest */ }

enum ObservabilityOTelPlanned {}
