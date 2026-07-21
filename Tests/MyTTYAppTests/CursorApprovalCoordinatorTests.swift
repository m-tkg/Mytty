import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Cursor approval coordinator")
struct CursorApprovalCoordinatorTests {
    private let surfaceID = TerminalSurfaceID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000101"
    )!)
    private let runID = AgentRunID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000201"
    )!)
    private let start = Date(timeIntervalSince1970: 1_721_113_200)

    @Test("delivers a synthetic approval-requested event once the threshold passes")
    @MainActor
    func deliversAfterThreshold() {
        var delivered: [AgentEvent] = []
        let coordinator = CursorApprovalCoordinator(
            threshold: 10,
            timerEnabled: false,
            deliver: { delivered.append($0) }
        )

        coordinator.observe(
            event(hookName: "preToolUse", toolUseID: "call-1", toolName: "Delete"),
            now: start
        )
        #expect(coordinator.nextDeadline == start.addingTimeInterval(10))

        coordinator.fireDue(now: start.addingTimeInterval(5))
        #expect(delivered.isEmpty)

        coordinator.fireDue(now: start.addingTimeInterval(10))
        #expect(delivered.count == 1)
        #expect(delivered.first?.kind == .approvalRequested)
        #expect(delivered.first?.runID == runID)
        #expect(delivered.first?.message == "Delete requires approval")
        #expect(coordinator.nextDeadline == nil)
    }

    @Test("does not deliver once postToolUse pairs by tool_use_id")
    @MainActor
    func skipsDeliveryOnceResolved() {
        var delivered: [AgentEvent] = []
        let coordinator = CursorApprovalCoordinator(
            threshold: 10,
            timerEnabled: false,
            deliver: { delivered.append($0) }
        )

        coordinator.observe(
            event(hookName: "preToolUse", toolUseID: "call-1", toolName: "Grep"),
            now: start
        )
        coordinator.observe(
            event(hookName: "postToolUse", toolUseID: "call-1", toolName: nil),
            now: start.addingTimeInterval(1)
        )
        #expect(coordinator.nextDeadline == nil)

        coordinator.fireDue(now: start.addingTimeInterval(30))
        #expect(delivered.isEmpty)
    }

    @Test("keeps a concurrent tool call pending when only the other one resolves")
    @MainActor
    func concurrentToolCallsResolveIndependently() {
        var delivered: [AgentEvent] = []
        let coordinator = CursorApprovalCoordinator(
            threshold: 10,
            timerEnabled: false,
            deliver: { delivered.append($0) }
        )

        coordinator.observe(
            event(hookName: "preToolUse", toolUseID: "call-grep", toolName: "Grep"),
            now: start
        )
        coordinator.observe(
            event(hookName: "preToolUse", toolUseID: "call-delete", toolName: "Delete"),
            now: start
        )
        coordinator.observe(
            event(hookName: "postToolUse", toolUseID: "call-grep", toolName: nil),
            now: start.addingTimeInterval(1)
        )

        coordinator.fireDue(now: start.addingTimeInterval(10))
        #expect(delivered.count == 1)
        #expect(delivered.first?.message == "Delete requires approval")
    }

    private func event(
        hookName: String,
        toolUseID: String,
        toolName: String?
    ) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            message: toolName,
            hookName: hookName,
            toolUseID: toolUseID
        )
    }
}
