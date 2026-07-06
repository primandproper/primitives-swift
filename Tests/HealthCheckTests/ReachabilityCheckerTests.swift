import Observability
import Testing

@testable import HealthCheck

@Suite("ReachabilityChecker")
struct ReachabilityCheckerTests {
  @Test("reports its configured name")
  func reportsName() {
    #expect(ReachabilityChecker(name: "wifi").name == "wifi")
  }

  @Test("defaults its name to \"reachability\"")
  func defaultName() {
    #expect(ReachabilityChecker().name == "reachability")
  }

  @Test(
    "check() resolves promptly through HealthCheckRegistry's timeout race, whichever way the current path resolves",
    .timeLimit(.minutes(1))
  )
  func checkResolvesPromptly() async {
    // The actual up/down outcome depends on the test host's live network state, which this suite can't
    // control hermetically — but it must always resolve (never hang) well inside the registry's default
    // timeout, and it must integrate cleanly with the registry's concurrent aggregation.
    let registry = HealthCheckRegistry(observer: recordingObserver("test"))
    await registry.register(ReachabilityChecker())

    let result = await registry.checkAll()

    #expect(result.components.count == 1)
    #expect(result.components["reachability"] != nil)
  }
}
