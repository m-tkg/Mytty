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

    @Test("a run starting or ending expires the pane's status note")
    @MainActor
    func statusNoteLifecycle() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let otherSurfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        center.setStatusNote("running tests", for: surfaceID)
        center.setStatusNote("unrelated", for: otherSurfaceID)
        #expect(center.statusNote(for: surfaceID) == "running tests")

        // Mid-run transitions keep the note alive.
        try center.append(harness.event(
            runID: runID,
            surfaceID: surfaceID,
            kind: .approvalRequested,
            at: 1
        ))
        #expect(center.statusNote(for: surfaceID) == "running tests")
        try center.append(harness.event(
            runID: runID,
            surfaceID: surfaceID,
            kind: .running,
            at: 2
        ))
        #expect(center.statusNote(for: surfaceID) == "running tests")

        // A terminal event clears it; other panes are untouched.
        try center.append(harness.event(
            runID: runID,
            surfaceID: surfaceID,
            kind: .succeeded,
            at: 3
        ))
        #expect(center.statusNote(for: surfaceID) == nil)
        #expect(center.statusNote(for: otherSurfaceID) == "unrelated")

        // A fresh run must not inherit the previous run's note either.
        center.setStatusNote("stale", for: surfaceID)
        try center.append(harness.event(
            runID: AgentRunID(),
            surfaceID: surfaceID,
            kind: .started,
            at: 4
        ))
        #expect(center.statusNote(for: surfaceID) == nil)

        center.setStatusNote("cleared by hand", for: surfaceID)
        center.clearStatusNote(for: surfaceID)
        #expect(center.statusNote(for: surfaceID) == nil)
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
        // Deliberately close to the real wall clock, not the epoch-based
        // timestamps most tests use: the idle run below has no attention
        // item at all, and `append`'s terminal-transition prune trigger
        // compares its `updatedAt` against a real `Date()`, so an
        // epoch-1970 timestamp would read as decades past
        // `AttentionPolicy.resolvedRetention` and get pruned before this
        // test ever gets to assert on it.
        let now = Date()

        try center.append(AgentEvent(
            runID: AgentRunID(),
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .started,
            occurredAt: now
        ))
        try center.append(AgentEvent(
            runID: AgentRunID(),
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .idle,
            occurredAt: now.addingTimeInterval(1)
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

    @Test("closing several panes acknowledges their items in one pass")
    @MainActor
    func acknowledgeClosedPanes() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let firstClosed = TerminalSurfaceID()
        let secondClosed = TerminalSurfaceID()
        let survivingSurface = TerminalSurfaceID()

        for (runID, surfaceID, request) in [
            (AgentRunID(), firstClosed, AgentEventKind.approvalRequested),
            (AgentRunID(), secondClosed, AgentEventKind.inputRequested),
            (AgentRunID(), survivingSurface, AgentEventKind.approvalRequested),
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
            for: [firstClosed, secondClosed],
            at: Date(timeIntervalSince1970: 10)
        )

        #expect(acknowledged == 2)
        #expect(center.actionableCount(for: [firstClosed, secondClosed]) == 0)
        #expect(center.actionableCount(for: [survivingSurface]) == 1)
        #expect(
            center.items.filter { $0.surfaceID != survivingSurface }
                .allSatisfy { $0.acknowledgedAt != nil }
        )
    }

    @Test("acknowledging unrelated surfaces leaves items untouched")
    @MainActor
    func acknowledgeUnrelatedSurfaces() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surface = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID, surfaceID: surface, kind: .started, at: 1
        ))
        try center.append(harness.event(
            runID: runID,
            surfaceID: surface,
            kind: .approvalRequested,
            at: 2
        ))

        let acknowledged = try center.acknowledgeActionableItems(
            for: [TerminalSurfaceID(), TerminalSurfaceID()],
            at: Date(timeIntervalSince1970: 10)
        )

        #expect(acknowledged == 0)
        #expect(center.actionableCount(for: [surface]) == 1)
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

    @Test("startup sweep disconnects a run a previous launch left running, and a second sweep is a no-op")
    @MainActor
    func sweepInterruptedRuns() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        // Simulate a run replayed from a previous app instance that
        // crashed while a Claude Code turn was still in flight -- no
        // terminal event was ever recorded for it.
        try center.append(harness.event(
            runID: runID,
            surfaceID: surfaceID,
            kind: .started,
            at: 1
        ))
        #expect(center.runs[runID]?.state == .running)

        try center.sweepInterruptedRuns(now: Date(timeIntervalSince1970: 10))

        #expect(center.runs[runID]?.state == .disconnected)

        // A second sweep on a later launch appends nothing new: the
        // deterministic sweep event ID is already recorded, so `append`
        // reports it as a duplicate.
        let eventCountAfterFirstSweep = try harness.repository.loadEvents().count
        try center.sweepInterruptedRuns(now: Date(timeIntervalSince1970: 20))
        #expect(try harness.repository.loadEvents().count == eventCountAfterFirstSweep)
        #expect(center.runs[runID]?.state == .disconnected)
    }

    @Test("a single sweep call closes out every stale run left non-terminal")
    @MainActor
    func sweepInterruptedRunsBatchesMultipleStaleRuns() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()

        // Three runs left non-terminal by a previous app instance, as if
        // the process had died mid-turn for each of them independently
        // (e.g. after a long-neglected log accumulated many stale runs
        // before the sweep first shipped).
        let runningRun = AgentRunID()
        let waitingInputRun = AgentRunID()
        let waitingApprovalRun = AgentRunID()

        try center.append(harness.event(
            runID: runningRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 1
        ))
        try center.append(harness.event(
            runID: waitingInputRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 2
        ))
        try center.append(harness.event(
            runID: waitingInputRun,
            surfaceID: surfaceID,
            kind: .inputRequested,
            at: 3
        ))
        try center.append(harness.event(
            runID: waitingApprovalRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 4
        ))
        try center.append(harness.event(
            runID: waitingApprovalRun,
            surfaceID: surfaceID,
            kind: .approvalRequested,
            at: 5
        ))
        #expect(center.runs[runningRun]?.state == .running)
        #expect(center.runs[waitingInputRun]?.state == .waitingInput)
        #expect(center.runs[waitingApprovalRun]?.state == .waitingApproval)

        try center.sweepInterruptedRuns(now: Date(timeIntervalSince1970: 100))

        #expect(center.runs[runningRun]?.state == .disconnected)
        #expect(center.runs[waitingInputRun]?.state == .disconnected)
        #expect(center.runs[waitingApprovalRun]?.state == .disconnected)
    }

    @Test("in-memory updates after append and acknowledge match a fresh disk reload")
    @MainActor
    func inMemoryUpdatesMatchDiskReload() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let requestRun = AgentRunID()
        let completedRun = AgentRunID()

        // Drive every in-memory update path: append(_:) for new events,
        // then an acknowledge call, so `runs`/`items` are built up purely
        // from in-memory replays rather than any disk reload.
        try center.append(harness.event(
            runID: requestRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 1
        ))
        try center.append(harness.event(
            runID: requestRun,
            surfaceID: surfaceID,
            kind: .approvalRequested,
            at: 2
        ))
        try center.append(harness.event(
            runID: completedRun,
            surfaceID: surfaceID,
            kind: .started,
            at: 3
        ))
        try center.append(harness.event(
            runID: completedRun,
            surfaceID: surfaceID,
            kind: .succeeded,
            at: 4
        ))

        let acknowledgedAt = Date(timeIntervalSince1970: 100)
        let acknowledgedCount = try center.acknowledgeActionableItems(
            for: surfaceID,
            at: acknowledgedAt
        )
        // Both the approval request and the completion are actionable.
        #expect(acknowledgedCount == 2)

        // A second center over the same on-disk database, reloaded fresh
        // from disk at the same `now`, must land on the exact same
        // derived state as the in-memory-only updates above.
        let reloaded = harness.center
        try reloaded.reload(now: acknowledgedAt)

        #expect(center.runs == reloaded.runs)
        #expect(center.items == reloaded.items)
    }

    @Test("prune removes a terminal run past retention with nothing actionable left")
    @MainActor
    func pruneRemovesRetiredRun() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .started, at: 1
        ))
        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .succeeded, at: 2
        ))

        let acknowledgedAt = Date(timeIntervalSince1970: 100)
        _ = try center.acknowledgeAllActionableItems(at: acknowledgedAt)

        let now = acknowledgedAt.addingTimeInterval(
            AttentionPolicy().resolvedRetention + 1
        )
        let prunedCount = try center.prune(now: now)

        #expect(prunedCount == 2)
        #expect(center.runs[runID] == nil)
        #expect(!center.items.contains { $0.runID == runID })
        #expect(
            try harness.repository.loadEvents()
                .allSatisfy { $0.runID != runID }
        )
        #expect(try harness.repository.loadAcknowledgements().isEmpty)
    }

    @Test("prune keeps a terminal run that still has an actionable item")
    @MainActor
    func pruneKeepsRunWithActionableItem() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .started, at: 1
        ))
        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .failed, at: 2
        ))

        // Never acknowledged, so the failure item stays actionable no
        // matter how old the run gets.
        let now = Date(
            timeIntervalSince1970: 2 + AttentionPolicy().resolvedRetention * 10
        )
        let prunedCount = try center.prune(now: now)

        #expect(prunedCount == 0)
        #expect(center.runs[runID]?.state == .failed)
        #expect(
            center.items.contains { $0.runID == runID && $0.isActionable }
        )
    }

    @Test("prune keeps a terminal run still inside the retention window")
    @MainActor
    func pruneKeepsRecentRun() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .started, at: 1
        ))
        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .succeeded, at: 2
        ))

        let acknowledgedAt = Date(timeIntervalSince1970: 100)
        _ = try center.acknowledgeAllActionableItems(at: acknowledgedAt)

        let now = acknowledgedAt.addingTimeInterval(
            AttentionPolicy().resolvedRetention - 10
        )
        let prunedCount = try center.prune(now: now)

        #expect(prunedCount == 0)
        #expect(center.runs[runID] != nil)
        #expect(center.items.contains { $0.runID == runID })
    }

    @Test("prune keeps a non-terminal run no matter how old")
    @MainActor
    func pruneKeepsActiveRun() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .started, at: 1
        ))

        let now = Date(
            timeIntervalSince1970: 1 + AttentionPolicy().resolvedRetention * 10
        )
        let prunedCount = try center.prune(now: now)

        #expect(prunedCount == 0)
        #expect(center.runs[runID]?.state == .running)
    }

    @Test("a run's terminal transition prunes it immediately once past retention")
    @MainActor
    func appendTriggersPruneOnTerminalTransition() throws {
        let harness = AttentionHarness()
        defer { harness.remove() }
        let center = harness.center
        let surfaceID = TerminalSurfaceID()
        let runID = AgentRunID()

        // Both events are timestamped decades in the past, so by the time
        // `append` prunes using the real wall clock, the run is already
        // long past `AttentionPolicy.resolvedRetention` -- no need to
        // inject a fake clock into `append` itself to observe the
        // terminal-transition trigger.
        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .started, at: 1
        ))
        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .approvalRequested, at: 2
        ))
        #expect(center.runs[runID]?.state == .waitingApproval)

        // Disconnecting resolves the pending approval item (no longer
        // actionable) and carries the run into a terminal state in the
        // same append call.
        try center.append(harness.event(
            runID: runID, surfaceID: surfaceID, kind: .disconnected, at: 3
        ))

        #expect(center.runs[runID] == nil)
        #expect(!center.items.contains { $0.runID == runID })
        #expect(
            try harness.repository.loadEvents()
                .allSatisfy { $0.runID != runID }
        )
    }
}

@MainActor
private struct AttentionHarness {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    var center: AttentionCenter {
        AttentionCenter(repository: repository)
    }

    var repository: SQLiteAgentEventRepository {
        SQLiteAgentEventRepository(
            databaseURL: directory.appendingPathComponent("mytty.sqlite")
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
