import Foundation
import Testing
@testable import MyTTYCore

@Suite("Antigravity turn run resolver")
struct AntigravityTurnRunResolverTests {
    private let surface = TerminalSurfaceID()
    private let conversation = "conv-1"
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func event(_ kind: AgentEventKind, at offset: TimeInterval) -> AgentEvent {
        // Like the adapter, the id depends on the payload only, so the same
        // kind of event in a later turn carries the same id.
        AgentEvent(
            id: AgentEventID(rawValue: StableAgentUUID.make(from: "agy-\(kind.rawValue)")),
            runID: AntigravityTurnRunResolver.baseRunID(conversationID: conversation),
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

    @Test("a late duplicate Stop after the turn ended opens no new run")
    func lateStopOpensNothing() {
        let result = feed([.running, .succeeded, .running, .succeeded, .succeeded, .failed])
        #expect(Set(result.events.map(\.runID)).count == 2)
    }

    @Test("a turn after .disconnected opens a new run")
    func afterDisconnected() {
        let result = feed([.running, .disconnected, .running])
        #expect(Set(result.events.map(\.runID)).count == 2)
        #expect(result.runs[result.events[2].runID]?.state == .running)
    }

    @Test("pruned earlier turns do not misroute events of the newest turn")
    func prunedHistory() {
        let all = feed([.running, .succeeded, .running, .succeeded, .running])
        let newest = all.events[4].runID
        // Only the in-progress newest run survives pruning.
        let survivors = all.runs.values.filter { $0.id == newest }
        let stop = AntigravityTurnRunResolver.resolve(
            event(.succeeded, at: 10), existingRuns: Array(survivors))
        #expect(stop.runID == newest)
        // After it finishes and is pruned too, the next turn still opens a
        // run distinct from every earlier one.
        let next = AntigravityTurnRunResolver.resolve(event(.running, at: 20), existingRuns: [])
        #expect(next.runID == AntigravityTurnRunResolver.baseRunID(conversationID: conversation))
        let fresh = AntigravityTurnRunResolver.resolve(
            event(.running, at: 30),
            existingRuns: Array(AgentEventReducer.reduce([event(.running, at: 21), event(.succeeded, at: 22)]).values))
        #expect(fresh.runID != newest)
        #expect(!all.events.prefix(4).map(\.runID).contains(fresh.runID))
    }

    @Test("a redelivered opening event maps to the same run and id")
    func redeliveryIdempotent() {
        let done = AgentEventReducer.reduce([event(.running, at: 0), event(.succeeded, at: 1)])
        let opener = event(.running, at: 5)
        let a = AntigravityTurnRunResolver.resolve(opener, existingRuns: Array(done.values))
        let b = AntigravityTurnRunResolver.resolve(opener, existingRuns: Array(done.values))
        #expect(a == b)
    }

    @Test("other providers are untouched")
    func otherProvider() {
        let e = AgentEvent(
            runID: AntigravityTurnRunResolver.baseRunID(conversationID: conversation),
            sessionID: conversation, surfaceID: surface, provider: .codex,
            kind: .running, occurredAt: t0)
        #expect(AntigravityTurnRunResolver.resolve(e, existingRuns: []) == e)
    }
}
