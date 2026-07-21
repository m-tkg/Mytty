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
            event(hookName: "beforeShellExecution", message: "rm -rf build"),
            now: start
        )
        #expect(coordinator.nextDeadline == start.addingTimeInterval(10))

        coordinator.fireDue(now: start.addingTimeInterval(5))
        #expect(delivered.isEmpty)

        coordinator.fireDue(now: start.addingTimeInterval(10))
        #expect(delivered.count == 1)
        #expect(delivered.first?.kind == .approvalRequested)
        #expect(delivered.first?.runID == runID)
        #expect(delivered.first?.message == "rm -rf build")
        #expect(coordinator.nextDeadline == nil)
    }

    @Test("does not deliver once afterShellExecution pairs by command")
    @MainActor
    func skipsDeliveryOnceResolved() {
        var delivered: [AgentEvent] = []
        let coordinator = CursorApprovalCoordinator(
            threshold: 10,
            timerEnabled: false,
            deliver: { delivered.append($0) }
        )

        coordinator.observe(
            event(hookName: "beforeShellExecution", message: "ls"),
            now: start
        )
        coordinator.observe(
            event(hookName: "afterShellExecution", message: "ls"),
            now: start.addingTimeInterval(1)
        )
        #expect(coordinator.nextDeadline == nil)

        coordinator.fireDue(now: start.addingTimeInterval(30))
        #expect(delivered.isEmpty)
    }

    private func event(hookName: String, message: String) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .running,
            occurredAt: start,
            message: message,
            hookName: hookName
        )
    }
}
