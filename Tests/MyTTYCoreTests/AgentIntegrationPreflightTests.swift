import Testing

@testable import MyTTYCore

@Suite("Agent integration preflight")
struct AgentIntegrationPreflightTests {
    @Test("maps integration status to the documented spawn failure codes")
    func mapsFailureCodes() {
        #expect(
            AgentIntegrationPreflight.failureCode(for: .notInstalled)
                == "provider-integration-not-installed"
        )
        #expect(
            AgentIntegrationPreflight.failureCode(for: .needsRepair)
                == "provider-integration-needs-repair"
        )
        #expect(AgentIntegrationPreflight.failureCode(for: .installed) == nil)
    }
}
