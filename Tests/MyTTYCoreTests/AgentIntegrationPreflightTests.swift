import Testing

@testable import MyTTYCore

@Suite("Agent integration preflight")
struct AgentIntegrationPreflightTests {
    @Test("spawn preflight only fails a needs-repair integration")
    func mapsFailureCodes() {
        // Native run estimation binds a spawned job to an estimated run,
        // so a not-installed provider no longer fails spawn.
        #expect(AgentIntegrationPreflight.failureCode(for: .notInstalled) == nil)
        #expect(
            AgentIntegrationPreflight.failureCode(for: .needsRepair)
                == "provider-integration-needs-repair"
        )
        #expect(AgentIntegrationPreflight.failureCode(for: .installed) == nil)
    }

    @Test(
        "the pane wait preflight only fails an attention wait against a not-installed integration",
        arguments: [
            (AgentIntegrationStatus.notInstalled, ControlWaitCondition.idle, nil),
            (
                .notInstalled, .attention,
                "provider-integration-not-installed"
            ),
            (.needsRepair, .idle, nil),
            (.needsRepair, .attention, nil),
            (.installed, .idle, nil),
            (.installed, .attention, nil),
        ] as [(AgentIntegrationStatus, ControlWaitCondition, String?)]
    )
    func waitFailureCodes(
        status: AgentIntegrationStatus,
        condition: ControlWaitCondition,
        expected: String?
    ) {
        #expect(
            AgentIntegrationPreflight.waitFailureCode(
                for: status,
                until: condition
            ) == expected
        )
    }

    @Test(
        "the agent wait preflight only fails an attention wait against a not-installed integration",
        arguments: [
            (AgentIntegrationStatus.notInstalled, AgentWaitCondition.running, nil),
            (.notInstalled, .completed, nil),
            (
                .notInstalled, .attention,
                "provider-integration-not-installed"
            ),
            (.needsRepair, .running, nil),
            (.needsRepair, .attention, nil),
            (.needsRepair, .completed, nil),
            (.installed, .running, nil),
            (.installed, .attention, nil),
            (.installed, .completed, nil),
        ] as [(AgentIntegrationStatus, AgentWaitCondition, String?)]
    )
    func agentWaitFailureCodes(
        status: AgentIntegrationStatus,
        condition: AgentWaitCondition,
        expected: String?
    ) {
        #expect(
            AgentIntegrationPreflight.agentWaitFailureCode(
                for: status,
                until: condition
            ) == expected
        )
    }
}
