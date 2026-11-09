import Foundation
import Testing
@testable import MyTTYCore

@Suite("Antigravity turn run resolver")
struct AntigravityTurnRunResolverTests {
    private let surface = TerminalSurfaceID()
    private let conversation = "conv-1"
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func event(_ kind: AgentEventKind, at offset: TimeInterval) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(),
            runID: AntigravityTurnRunResolver.runID(conversationID: conversation, turn: 0),
            sessionID: conversation,
            surfaceID: surface,
            provider: .antigravity,
            kind: kind,
            occurredAt: t0.addingTimeInterval(offset)
        )
    }

    /// Feeds events through the resolver the way `receiveAgentEvent` does.
    private func feed(_ kinds: [AgentEventKind]) -> (events: [AgentEvent], runs: [AgentRunID: AgentRun]) {
        var applied: [AgentEvent] = []
        for (i, kind) in kinds.enumerated() {
            let runs = Array(AgentEventReducer.reduce(applied).values)
            applied.append(
                AntigravityTurnRunResolver.resolve(event(kind, at: Double(i)), existingRuns: runs))
        }
        return (applied, AgentEventReducer.reduce(applied))
    }

    @Test("a second turn after Stop opens a new run")
    func secondTurnGetsNewRun() {
        let result = feed([.running, .running, .succeeded, .running, .running, .succeeded])
        let ids = Set(result.events.map(\.runID))
        #expect(ids.count == 2)
        #expect(result.runs.values.allSatisfy { $0.state == .succeeded })
        #expect(result.events[3].runID != result.events[0].runID)
        #expect(result.events[5].runID == result.events[3].runID)
    }

    @Test("a second turn in progress leaves the first run finished and itself running")
    func secondTurnRunning() {
        let result = feed([.running, .succeeded, .running])
        let latest = result.runs[result.events[2].runID]
        #expect(latest?.state == .running)
        #expect(result.runs[result.events[0].runID]?.state == .succeeded)
    }

    @Test("a third turn gets a third run")
    func thirdTurn() {
        let result = feed([.running, .succeeded, .running, .failed, .running])
        #expect(Set(result.events.map(\.runID)).count == 3)
    }

    @Test("the first turn keeps the adapter's run ID")
    func firstTurnUnchanged() {
        let result = feed([.running, .running, .succeeded])
        #expect(Set(result.events.map(\.runID)).count == 1)
    }

    @Test("other providers are untouched")
    func otherProvider() {
        let e = AgentEvent(
            runID: AntigravityTurnRunResolver.runID(conversationID: conversation, turn: 0),
            sessionID: conversation, surfaceID: surface, provider: .codex,
            kind: .running, occurredAt: t0)
        #expect(AntigravityTurnRunResolver.resolve(e, existingRuns: []) == e)
    }
}
