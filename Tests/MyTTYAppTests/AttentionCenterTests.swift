import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Attention center tab state")
struct AttentionCenterTests {
    @Test("active work replaces a terminal state from an older run")
    @MainActor
    func activeRunWinsOverHistory() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let oldRun = AgentRunID()
        let currentRun = AgentRunID()

        try center.append(harness.event(
            runID: oldRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 1
        ))
        try center.append(harness.event(
            runID: oldRun,
            surfaceID: surfaceID,
            kind: .failed,
            at: 2
        ))
        try center.append(harness.event(
            runID: currentRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 3
        ))

        #expect(center.mostRelevantState(for: [surfaceID]) == .running)
    }

    @Test("shows the newest result when no run remains active")
    @MainActor
    func newestTerminalState() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let oldRun = AgentRunID()
        let latestRun = AgentRunID()

        for event in [
            harness.event(
                runID: oldRun,
                surfaceID: surfaceID,
                kind: .started,
                at: 1
            ),
            harness.event(
                runID: oldRun,
                surfaceID: surfaceID,
                kind: .failed,
                at: 2
            ),
            harness.event(
                runID: latestRun,
                surfaceID: surfaceID,
                kind: .started,
                at: 3
            ),
            harness.event(
                runID: latestRun,
                surfaceID: surfaceID,
                kind: .succeeded,
                at: 4
            ),
        ] {
            try center.append(event)
        }

        #expect(center.mostRelevantState(for: [surfaceID]) == .succeeded)
    }

    @Test("reports the provider only while work is active on a surface")
    @MainActor
    func activeProvider() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let activeSurface = TerminalSurfaceID()
        let otherSurface = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID,
            surfaceID: activeSurface,
            provider: .claudeCode,
            kind: .started,
            at: 1
        ))
        try center.append(harness.event(
            runID: runID,
            surfaceID: activeSurface,
            provider: .claudeCode,
            kind: .approvalRequested,
            at: 2
        ))

        #expect(center.activeProvider(for: activeSurface) == .claudeCode)
        #expect(center.activeProvider(for: otherSurface) == nil)

        try center.append(harness.event(
            runID: runID,
            surfaceID: activeSurface,
            provider: .claudeCode,
            kind: .running,
            at: 3
        ))
        try center.append(harness.event(
            runID: runID,
            surfaceID: activeSurface,
            provider: .claudeCode,
            kind: .succeeded,
            at: 4
        ))

        #expect(center.activeProvider(for: activeSurface) == nil)
    }

    @Test("retains the latest agent for a surface after work completes")
    @MainActor
    func mostRelevantRun() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .started,
            at: 1
        ))
        try center.append(harness.event(
            runID: runID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .succeeded,
            at: 2
        ))

        let run = center.mostRelevantRun(for: surfaceID)
        #expect(run?.provider == .cursor)
        #expect(run?.state == .succeeded)
        #expect(center.mostRelevantRun(for: TerminalSurfaceID()) == nil)
    }

    @Test("a new idle session supersedes stale processing on a reused surface")
    @MainActor
    func idleSessionSupersedesStaleRun() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()

        try center.append(harness.event(
            runID: AgentRunID(),
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .started,
            at: 1
        ))
        try center.append(harness.event(
            runID: AgentRunID(),
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .idle,
            at: 2
        ))

        #expect(center.latestRun(
            for: surfaceID,
            provider: .claudeCode
        )?.state == .idle)
    }

    @Test("acknowledges every actionable item for the focused pane")
    @MainActor
    func acknowledgeFocusedPane() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let focusedSurface = TerminalSurfaceID()
        let otherSurface = TerminalSurfaceID()

        for (runID, surfaceID, request) in [
            (AgentRunID(), focusedSurface, AgentEventKind.approvalRequested),
            (AgentRunID(), focusedSurface, AgentEventKind.inputRequested),
            (AgentRunID(), otherSurface, AgentEventKind.approvalRequested),
        ] {
            try center.append(harness.event(
                runID: runID,
                surfaceID: surfaceID,
                kind: .started,
                at: 1
            ))
            try center.append(harness.event(
                runID: runID,
                surfaceID: surfaceID,
                kind: request,
                at: 2
            ))
        }

        let acknowledged = try center.acknowledgeActionableItems(
            for: focusedSurface,
            at: Date(timeIntervalSince1970: 10)
        )

        #expect(acknowledged == 2)
        #expect(center.actionableCount(for: [focusedSurface]) == 0)
        #expect(center.actionableCount(for: [otherSurface]) == 1)
        #expect(
            center.items.filter { $0.surfaceID == focusedSurface }
                .allSatisfy { $0.acknowledgedAt != nil }
        )
    }

    @Test("startup sweep clears only completions from before the cutoff")
    @MainActor
    func acknowledgeStaleCompletions() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let staleRun = AgentRunID()
        let freshRun = AgentRunID()
        let requestRun = AgentRunID()
        let surface = TerminalSurfaceID()

        try center.append(harness.event(
            runID: staleRun, surfaceID: surface, kind: .started, at: 1
        ))
        try center.append(harness.event(
            runID: staleRun, surfaceID: surface, kind: .succeeded, at: 2
        ))
        try center.append(harness.event(
            runID: requestRun, surfaceID: surface, kind: .started, at: 3
        ))
        try center.append(harness.event(
            runID: requestRun,
            surfaceID: surface,
            kind: .approvalRequested,
            at: 4
        ))
        try center.append(harness.event(
            runID: freshRun, surfaceID: surface, kind: .started, at: 20
        ))
        try center.append(harness.event(
            runID: freshRun, surfaceID: surface, kind: .succeeded, at: 21
        ))

        let acknowledged = try center.acknowledgeCompletions(
            before: Date(timeIntervalSince1970: 10),
            at: Date(timeIntervalSince1970: 30)
        )

        #expect(acknowledged == 1)
        let actionable = center.items.filter(\.isActionable)
        // The pre-cutoff completion is gone; the request from before the
        // cutoff and the completion from after it both stay unread.
        #expect(
            actionable.map(\.kind).sorted { $0.rawValue < $1.rawValue }
                == [.approvalRequest, .completion]
        )
        #expect(actionable.map(\.runID).contains(freshRun))
        #expect(!actionable.map(\.runID).contains(staleRun))
    }

    @Test("clear-all acknowledges every actionable item across surfaces")
    @MainActor
    func acknowledgeAllActionableItems() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let firstSurface = TerminalSurfaceID()
        let secondSurface = TerminalSurfaceID()

        for (runID, surfaceID, request) in [
            (AgentRunID(), firstSurface, AgentEventKind.approvalRequested),
            (AgentRunID(), secondSurface, AgentEventKind.inputRequested),
        ] {
            try center.append(harness.event(
                runID: runID,
                surfaceID: surfaceID,
                kind: .started,
                at: 1
            ))
            try center.append(harness.event(
                runID: runID,
                surfaceID: surfaceID,
                kind: request,
                at: 2
            ))
        }
        #expect(center.actionableCount == 2)

        let acknowledged = try center.acknowledgeAllActionableItems(
            at: Date(timeIntervalSince1970: 10)
        )

        #expect(acknowledged == 2)
        #expect(center.actionableCount == 0)
        #expect(center.items.allSatisfy { $0.acknowledgedAt != nil })
        // A second clear finds nothing left to acknowledge.
        #expect(try center.acknowledgeAllActionableItems() == 0)
    }
}

@MainActor
private struct AttentionHarness {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    var center: AttentionCenter {
        AttentionCenter(
            repository: SQLiteAgentEventRepository(
                databaseURL: directory.appendingPathComponent("mytty.sqlite")
            )
        )
    }

    func event(
        runID: AgentRunID,
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider = .codex,
        kind: AgentEventKind,
        at time: TimeInterval
    ) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: provider,
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: time)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
