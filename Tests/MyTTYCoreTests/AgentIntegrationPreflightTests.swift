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

    @Test("the wait preflight only fails a not-installed integration")
    func waitFailureCodes() {
        #expect(
            AgentIntegrationPreflight.waitFailureCode(for: .notInstalled)
                == "provider-integration-not-installed"
        )
        // needs-repair may still deliver events from a live session, so a
        // wait against it must keep waiting rather than fail.
        #expect(
            AgentIntegrationPreflight.waitFailureCode(for: .needsRepair) == nil
        )
        #expect(
            AgentIntegrationPreflight.waitFailureCode(for: .installed) == nil
        )
    }
}
