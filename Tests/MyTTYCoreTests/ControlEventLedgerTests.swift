import Foundation
import Testing

@testable import MyTTYCore

@Suite("Control event ledger")
struct ControlEventLedgerTests {
    @Test("assigns sequence numbers starting at 1 and tracks the latest")
    @MainActor
    func sequencing() {
        let ledger = ControlEventLedger()
        #expect(ledger.latestSequence == 0)

        let first = ledger.append(makeEvent(kind: .started))
        #expect(first.sequence == 1)
        #expect(ledger.latestSequence == 1)

        let second = ledger.append(makeEvent(kind: .idle))
        #expect(second.sequence == 2)
        #expect(ledger.latestSequence == 2)
    }

    @Test("records(after:) returns only newer records, oldest first")
    @MainActor
    func recordsAfter() {
        let ledger = ControlEventLedger()
        ledger.append(makeEvent(kind: .started))
        ledger.append(makeEvent(kind: .running))
        ledger.append(makeEvent(kind: .idle))

        #expect(ledger.records(after: 0).map(\.sequence) == [1, 2, 3])
        #expect(ledger.records(after: 1).map(\.sequence) == [2, 3])
        #expect(ledger.records(after: 3).isEmpty)
    }

    @Test("records(after:limit:) caps the result")
    @MainActor
    func recordsAfterLimit() {
        let ledger = ControlEventLedger()
        for _ in 1...5 {
            ledger.append(makeEvent(kind: .running))
        }
        #expect(ledger.records(after: 0, limit: 2).map(\.sequence) == [1, 2])
    }

    @Test("evicts the oldest record once capacity is exceeded")
    @MainActor
    func eviction() {
        let ledger = ControlEventLedger(capacity: 3)
        for _ in 1...5 {
            ledger.append(makeEvent(kind: .running))
        }
        // Only the three most recently appended records survive.
        #expect(ledger.records(after: 0).map(\.sequence) == [3, 4, 5])
    }

    @Test("latestSequence is unaffected by eviction")
    @MainActor
    func latestSequenceSurvivesEviction() {
        let ledger = ControlEventLedger(capacity: 2)
        for _ in 1...10 {
            ledger.append(makeEvent(kind: .running))
        }
        #expect(ledger.latestSequence == 10)
        #expect(ledger.records(after: 0).map(\.sequence) == [9, 10])
    }

    @Test("records(after:) with a sequence older than the oldest retained record returns what's retained, not an error")
    @MainActor
    func staleCursorSkipsEvictedHistory() {
        let ledger = ControlEventLedger(capacity: 2)
        for _ in 1...5 {
            ledger.append(makeEvent(kind: .running))
        }
        // Sequence 1 was evicted long ago; the cursor contract is
        // at-most-once delivery of what's retained, not a hard failure.
        #expect(ledger.records(after: 1).map(\.sequence) == [4, 5])
    }

    @Test("a record captures the fields mytty-ctl events needs")
    @MainActor
    func recordFields() {
        let ledger = ControlEventLedger()
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()
        let occurredAt = Date()
        let record = ledger.append(
            AgentEvent(
                runID: runID,
                surfaceID: surfaceID,
                provider: .claudeCode,
                kind: .approvalRequested,
                occurredAt: occurredAt,
                toolName: "Bash"
            )
        )
        #expect(record.sequence == 1)
        #expect(record.paneID == surfaceID.rawValue.uuidString)
        #expect(record.provider == "claude-code")
        #expect(record.runID == runID.rawValue.uuidString)
        #expect(record.kind == "approval-requested")
        #expect(record.occurredAt == occurredAt)
        #expect(record.toolName == "Bash")
        #expect(record.synthesized == false)
    }

    @Test("marks a mytty-synthesized event as synthesized")
    @MainActor
    func synthesizedFlag() {
        let ledger = ControlEventLedger()
        let record = ledger.append(
            AgentEvent(
                runID: AgentRunID(),
                surfaceID: TerminalSurfaceID(),
                provider: .codex,
                kind: .idle,
                occurredAt: Date(),
                hookName: "mytty.native.commandFinished"
            )
        )
        #expect(record.synthesized == true)
    }

    private func makeEvent(kind: AgentEventKind) -> AgentEvent {
        AgentEvent(
            runID: AgentRunID(),
            surfaceID: TerminalSurfaceID(),
            provider: .codex,
            kind: kind,
            occurredAt: Date()
        )
    }
}
