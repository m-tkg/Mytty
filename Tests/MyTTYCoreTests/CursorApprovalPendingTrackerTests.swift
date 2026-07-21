import Foundation
import Testing

@testable import MyTTYCore

@Suite("Cursor approval pending tracker")
struct CursorApprovalPendingTrackerTests {
    private let surfaceID = TerminalSurfaceID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000101"
    )!)
    private let runID = AgentRunID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000201"
    )!)
    private let start = Date(timeIntervalSince1970: 1_721_113_200)

    @Test("fires an approval when nothing follows within the threshold")
    func firesWhenNothingFollows() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        let deadline = tracker.handle(
            preToolUse(toolUseID: "call-1", toolName: "Delete"),
            now: start
        )

        #expect(deadline == start.addingTimeInterval(10))
        #expect(tracker.fireDue(now: start.addingTimeInterval(9)).isEmpty)

        let fired = tracker.fireDue(now: start.addingTimeInterval(10))
        #expect(fired.count == 1)
        #expect(fired.first?.toolUseID == "call-1")
        #expect(fired.first?.toolName == "Delete")
        #expect(fired.first?.runID == runID)
        #expect(tracker.nextDeadline == nil)
    }

    @Test("cancels the pending approval when postToolUse pairs by tool_use_id")
    func cancelsOnMatchingPostToolUse() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(preToolUse(toolUseID: "call-1", toolName: "Grep"), now: start)
        let deadline = tracker.handle(
            postToolUse(toolUseID: "call-1"),
            now: start.addingTimeInterval(1)
        )

        #expect(deadline == nil)
        #expect(tracker.fireDue(now: start.addingTimeInterval(30)).isEmpty)
    }

    @Test("cancels the pending approval when postToolUseFailure pairs by tool_use_id")
    func cancelsOnMatchingPostToolUseFailure() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(preToolUse(toolUseID: "call-1", toolName: "Delete"), now: start)
        let deadline = tracker.handle(
            postToolUseFailure(toolUseID: "call-1"),
            now: start.addingTimeInterval(1)
        )

        #expect(deadline == nil)
        #expect(tracker.fireDue(now: start.addingTimeInterval(30)).isEmpty)
    }

    @Test(
        "leaves a still-pending tool call registered when only another concurrent tool call's postToolUse arrives"
    )
    func concurrentToolCallsArePairedIndependently() {
        // Reproduces the observed real-world ordering: Grep and Delete
        // both fire preToolUse back to back, then only Grep's
        // postToolUse arrives before the deadline — Delete (stuck on an
        // approval prompt) must stay pending.
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(preToolUse(toolUseID: "call-grep", toolName: "Grep"), now: start)
        tracker.handle(
            preToolUse(toolUseID: "call-delete", toolName: "Delete"),
            now: start
        )
        tracker.handle(
            postToolUse(toolUseID: "call-grep"),
            now: start.addingTimeInterval(1)
        )

        #expect(tracker.nextDeadline == start.addingTimeInterval(10))

        let fired = tracker.fireDue(now: start.addingTimeInterval(10))
        #expect(fired.count == 1)
        #expect(fired.first?.toolUseID == "call-delete")
        #expect(fired.first?.toolName == "Delete")
    }

    @Test("cancels every pending tool call for the run on stop")
    func cancelsAllOnStop() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(preToolUse(toolUseID: "call-1", toolName: "Grep"), now: start)
        tracker.handle(preToolUse(toolUseID: "call-2", toolName: "Delete"), now: start)
        let deadline = tracker.handle(
            AgentEvent(
                runID: runID,
                surfaceID: surfaceID,
                provider: .cursor,
                kind: .succeeded,
                occurredAt: start.addingTimeInterval(1),
                hookName: "stop"
            ),
            now: start.addingTimeInterval(1)
        )

        #expect(deadline == nil)
        #expect(tracker.fireDue(now: start.addingTimeInterval(30)).isEmpty)
    }

    @Test("cancels every pending tool call for the run on failed/disconnected")
    func cancelsAllOnFailedOrDisconnected() {
        for kind in [AgentEventKind.failed, .disconnected] {
            let tracker = CursorApprovalPendingTracker(threshold: 10)
            tracker.handle(preToolUse(toolUseID: "call-1", toolName: "Shell"), now: start)
            let deadline = tracker.handle(
                AgentEvent(
                    runID: runID,
                    surfaceID: surfaceID,
                    provider: .cursor,
                    kind: kind,
                    occurredAt: start.addingTimeInterval(1),
                    hookName: "stop"
                ),
                now: start.addingTimeInterval(1)
            )

            #expect(deadline == nil)
            #expect(tracker.fireDue(now: start.addingTimeInterval(30)).isEmpty)
        }
    }

    @Test("does not register twice for the same run and tool_use_id")
    func doesNotDuplicateRegistration() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(preToolUse(toolUseID: "call-1", toolName: "Grep"), now: start)
        tracker.handle(
            preToolUse(toolUseID: "call-1", toolName: "Grep"),
            now: start.addingTimeInterval(5)
        )

        // The deadline stays anchored to the first sighting, not the
        // second — otherwise a chatty hook could push it out forever.
        #expect(tracker.nextDeadline == start.addingTimeInterval(10))
    }

    @Test("ignores preToolUse with no tool_use_id")
    func ignoresMissingToolUseID() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        let deadline = tracker.handle(
            AgentEvent(
                runID: runID,
                surfaceID: surfaceID,
                provider: .cursor,
                kind: .running,
                occurredAt: start,
                message: "Delete",
                hookName: "preToolUse",
                toolUseID: nil
            ),
            now: start
        )

        #expect(deadline == nil)
    }

    @Test("ignores events from other providers")
    func ignoresOtherProviders() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        let deadline = tracker.handle(
            AgentEvent(
                runID: runID,
                surfaceID: surfaceID,
                provider: .claudeCode,
                kind: .running,
                occurredAt: start,
                message: "npm test",
                hookName: "preToolUse",
                toolUseID: "call-1"
            ),
            now: start
        )

        #expect(deadline == nil)
    }

    private func preToolUse(toolUseID: String, toolName: String) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            message: toolName,
            hookName: "preToolUse",
            toolUseID: toolUseID
        )
    }

    private func postToolUse(toolUseID: String) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            hookName: "postToolUse",
            toolUseID: toolUseID
        )
    }

    private func postToolUseFailure(toolUseID: String) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            hookName: "postToolUseFailure",
            toolUseID: toolUseID
        )
    }
}
