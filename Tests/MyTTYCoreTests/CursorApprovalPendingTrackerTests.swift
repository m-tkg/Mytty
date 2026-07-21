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
            beforeShellExecution(command: "rm -rf build"),
            now: start
        )

        #expect(deadline == start.addingTimeInterval(10))
        #expect(tracker.fireDue(now: start.addingTimeInterval(9)).isEmpty)

        let fired = tracker.fireDue(now: start.addingTimeInterval(10))
        #expect(fired.count == 1)
        #expect(fired.first?.command == "rm -rf build")
        #expect(fired.first?.runID == runID)
        #expect(tracker.nextDeadline == nil)
    }

    @Test("cancels the pending approval when afterShellExecution pairs by command")
    func cancelsOnMatchingAfterShellExecution() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(beforeShellExecution(command: "ls"), now: start)
        let deadline = tracker.handle(
            afterShellExecution(command: "ls"),
            now: start.addingTimeInterval(1)
        )

        #expect(deadline == nil)
        #expect(tracker.fireDue(now: start.addingTimeInterval(30)).isEmpty)
    }

    @Test("cancels every pending command for the run on stop")
    func cancelsAllOnStop() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(beforeShellExecution(command: "ls"), now: start)
        tracker.handle(beforeShellExecution(command: "pwd"), now: start)
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

    @Test("does not register twice for the same run and command")
    func doesNotDuplicateRegistration() {
        let tracker = CursorApprovalPendingTracker(threshold: 10)
        tracker.handle(beforeShellExecution(command: "ls"), now: start)
        tracker.handle(
            beforeShellExecution(command: "ls"),
            now: start.addingTimeInterval(5)
        )

        // The deadline stays anchored to the first sighting, not the
        // second — otherwise a chatty hook could push it out forever.
        #expect(tracker.nextDeadline == start.addingTimeInterval(10))
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
                hookName: "beforeShellExecution"
            ),
            now: start
        )

        #expect(deadline == nil)
    }

    private func beforeShellExecution(command: String) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            message: command,
            hookName: "beforeShellExecution"
        )
    }

    private func afterShellExecution(command: String) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            message: command,
            hookName: "afterShellExecution"
        )
    }
}
