import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent event reducer")
struct AgentEventReducerTests {
    @Test("applies valid transitions and ignores duplicate deliveries")
    func transitionsAndDeduplication() {
        let runID = AgentRunID(rawValue: makeUUID(1))
        let started = event(
            1,
            runID: runID,
            sessionID: "codex-session-01",
            kind: .started,
            at: 0
        )
        let approval = event(
            2,
            runID: runID,
            kind: .approvalRequested,
            at: 10
        )
        let resumed = event(3, runID: runID, kind: .running, at: 20)
        let succeeded = event(4, runID: runID, kind: .succeeded, at: 30)
        let duplicate = AgentEvent(
            id: succeeded.id,
            runID: runID,
            surfaceID: succeeded.surfaceID,
            provider: .codex,
            kind: .failed,
            occurredAt: date(40),
            message: "must be ignored"
        )

        let runs = AgentEventReducer.reduce([
            started,
            approval,
            resumed,
            succeeded,
            duplicate,
        ])

        #expect(runs[runID]?.state == .succeeded)
        #expect(runs[runID]?.sessionID == "codex-session-01")
        #expect(runs[runID]?.startedAt == date(0))
        #expect(runs[runID]?.updatedAt == date(30))
        #expect(runs[runID]?.acceptedEventCount == 4)
    }

    @Test("leaves a run unknown when lifecycle events arrive out of order")
    func invalidTransitions() {
        let runID = AgentRunID(rawValue: makeUUID(2))

        let runs = AgentEventReducer.reduce([
            event(1, runID: runID, kind: .inputRequested, at: 0),
            event(2, runID: runID, kind: .succeeded, at: 1),
        ])

        #expect(runs[runID]?.state == .unknown)
        #expect(runs[runID]?.acceptedEventCount == 0)
    }

    @Test("moves waiting runs back to running")
    func resumesWaitingRuns() {
        let inputRun = AgentRunID(rawValue: makeUUID(3))
        let approvalRun = AgentRunID(rawValue: makeUUID(4))

        let runs = AgentEventReducer.reduce([
            event(1, runID: inputRun, kind: .started, at: 0),
            event(2, runID: inputRun, kind: .inputRequested, at: 1),
            event(3, runID: inputRun, kind: .running, at: 2),
            event(4, runID: approvalRun, kind: .started, at: 0),
            event(5, runID: approvalRun, kind: .approvalRequested, at: 1),
            event(6, runID: approvalRun, kind: .running, at: 2),
        ])

        #expect(runs[inputRun]?.state == .running)
        #expect(runs[approvalRun]?.state == .running)
    }

    @Test("records an agent session waiting at its initial prompt as idle")
    func idleSession() {
        let runID = AgentRunID(rawValue: makeUUID(5))

        let runs = AgentEventReducer.reduce([
            event(1, runID: runID, kind: .idle, at: 0),
        ])

        #expect(runs[runID]?.state == .idle)
        #expect(runs[runID]?.startedAt == nil)
    }

    private func event(
        _ id: UInt8,
        runID: AgentRunID,
        sessionID: String? = nil,
        kind: AgentEventKind,
        at time: TimeInterval
    ) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(rawValue: makeUUID(id)),
            runID: runID,
            sessionID: sessionID,
            surfaceID: TerminalSurfaceID(rawValue: makeUUID(100)),
            provider: .codex,
            kind: kind,
            occurredAt: date(time)
        )
    }
}

@Suite("Attention policy")
struct AttentionReducerTests {
    private let policy = AttentionPolicy(
        resolvedRetention: 24 * 60 * 60
    )

    @Test("includes actionable events but excludes disconnections")
    func actionableEvents() {
        let runID = AgentRunID(rawValue: makeUUID(10))
        let events = [
            event(1, runID: runID, kind: .started, at: 0),
            event(2, runID: runID, kind: .inputRequested, at: 10),
            event(3, runID: runID, kind: .running, at: 20),
            event(4, runID: runID, kind: .approvalRequested, at: 30),
            event(5, runID: runID, kind: .disconnected, at: 40),
        ]

        let items = AttentionReducer.reduce(
            events: events,
            acknowledgements: [],
            now: date(50),
            policy: policy
        )

        #expect(items.map(\.kind) == [
            .approvalRequest,
            .inputRequest,
        ])
        #expect(items[0].resolvedAt == date(40))
        #expect(items[1].resolvedAt == date(20))
    }

    @Test("includes a completion for every successful run")
    func completionForEverySuccessfulRun() {
        let longRun = AgentRunID(rawValue: makeUUID(11))
        let shortRun = AgentRunID(rawValue: makeUUID(12))
        let failedRun = AgentRunID(rawValue: makeUUID(13))
        let events = [
            event(1, runID: longRun, kind: .started, at: 0),
            event(2, runID: longRun, kind: .succeeded, at: 301),
            event(3, runID: shortRun, kind: .started, at: 0),
            event(4, runID: shortRun, kind: .succeeded, at: 299),
            event(5, runID: failedRun, kind: .started, at: 0),
            event(6, runID: failedRun, kind: .failed, at: 1),
        ]

        let items = AttentionReducer.reduce(
            events: events,
            acknowledgements: [],
            now: date(400),
            policy: policy
        )

        #expect(
            items.map(\.kind) == [.completion, .completion, .failure]
        )
        #expect(items.map(\.runID) == [longRun, shortRun, failedRun])
    }

    @Test("retains acknowledged items for 24 hours")
    func acknowledgementRetention() {
        let runID = AgentRunID(rawValue: makeUUID(14))
        let request = event(
            2,
            runID: runID,
            kind: .approvalRequested,
            at: 10
        )
        let events = [
            event(1, runID: runID, kind: .started, at: 0),
            request,
        ]
        let acknowledgement = AttentionAcknowledgement(
            eventID: request.id,
            acknowledgedAt: date(20)
        )

        let retained = AttentionReducer.reduce(
            events: events,
            acknowledgements: [acknowledgement],
            now: date(20 + 23 * 60 * 60),
            policy: policy
        )
        let expired = AttentionReducer.reduce(
            events: events,
            acknowledgements: [acknowledgement],
            now: date(20 + 25 * 60 * 60),
            policy: policy
        )

        #expect(retained.count == 1)
        #expect(retained[0].acknowledgedAt == date(20))
        #expect(!retained[0].isActionable)
        #expect(expired.isEmpty)
    }

    private func event(
        _ id: UInt8,
        runID: AgentRunID,
        kind: AgentEventKind,
        at time: TimeInterval
    ) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(rawValue: makeUUID(id)),
            runID: runID,
            surfaceID: TerminalSurfaceID(rawValue: makeUUID(101)),
            provider: .claudeCode,
            kind: kind,
            occurredAt: date(time)
        )
    }
}

private func date(_ time: TimeInterval) -> Date {
    Date(timeIntervalSince1970: time)
}

private func makeUUID(_ value: UInt8) -> UUID {
    UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, value
    ))
}
