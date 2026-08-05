import Foundation
import Testing

@testable import MyTTYCore

@Suite("Native agent run estimator")
struct NativeAgentRunEstimatorTests {
    private let surfaceID = TerminalSurfaceID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000101"
    )!)
    private let start = Date(timeIntervalSince1970: 1_721_113_200)

    @Test("emits nothing before the start grace elapses, then exactly one started event")
    func firesStartedAfterGrace() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        let appeared = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 111,
            suppressedProviders: [],
            now: start
        )
        #expect(appeared.isEmpty)
        #expect(estimator.nextDeadline == start.addingTimeInterval(3))

        #expect(estimator.fireDue(now: start.addingTimeInterval(2)).isEmpty)

        let fired = estimator.fireDue(now: start.addingTimeInterval(3))
        #expect(fired.count == 1)
        #expect(fired[0].kind == .started)
        #expect(fired[0].provider == .codex)
        #expect(fired[0].hookName == "mytty.native.launchObserved")
        #expect(estimator.nextDeadline == nil)

        let runID = fired[0].runID
        // fireDue again produces nothing further -- the epoch already
        // transitioned to `started`.
        #expect(estimator.fireDue(now: start.addingTimeInterval(10)).isEmpty)
        #expect(runID == fired[0].runID)
    }

    @Test("a real hook event within the grace cancels the pending start for good")
    func realEventDuringGraceCancelsPendingStart() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .claudeCode,
            processID: 222,
            suppressedProviders: [],
            now: start
        )

        estimator.observeRealEvent(
            realHookEvent(provider: .claudeCode, kind: .started, hookName: "UserPromptSubmit")
        )

        #expect(estimator.fireDue(now: start.addingTimeInterval(3)).isEmpty)
        #expect(estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(4)
        ).isEmpty)
    }

    @Test("started then commandFinished with exit 0 succeeds; the following disappearance is silent")
    func startedThenSucceeded() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 333,
            suppressedProviders: [],
            now: start
        )
        let started = estimator.fireDue(now: start.addingTimeInterval(3))
        #expect(started.count == 1)

        let finished = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(10)
        )
        #expect(finished.count == 1)
        #expect(finished[0].kind == .succeeded)
        #expect(finished[0].runID == started[0].runID)
        #expect(finished[0].hookName == "mytty.native.commandFinished")

        // The process disappearing right after must not emit a second end.
        let disappeared = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: nil,
            processID: nil,
            suppressedProviders: [],
            now: start.addingTimeInterval(11)
        )
        #expect(disappeared.isEmpty)
    }

    @Test("started then commandFinished with a nonzero exit code fails")
    func startedThenFailed() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 444,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.fireDue(now: start.addingTimeInterval(3))

        let finished = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 2,
            now: start.addingTimeInterval(10)
        )
        #expect(finished.count == 1)
        #expect(finished[0].kind == .failed)
    }

    @Test("started then commandFinished with a nil exit code disconnects")
    func startedThenNilExitCodeDisconnects() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 555,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.fireDue(now: start.addingTimeInterval(3))

        let finished = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: nil,
            now: start.addingTimeInterval(10)
        )
        #expect(finished.count == 1)
        #expect(finished[0].kind == .disconnected)
    }

    @Test("started then the process disappearing without commandFinished disconnects")
    func startedThenDisappearsDisconnects() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 666,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.fireDue(now: start.addingTimeInterval(3))

        let disappeared = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: nil,
            processID: nil,
            suppressedProviders: [],
            now: start.addingTimeInterval(10)
        )
        #expect(disappeared.count == 1)
        #expect(disappeared[0].kind == .disconnected)
        #expect(disappeared[0].hookName == "mytty.native.processExited")
    }

    @Test("a suppressed provider is never tracked")
    func suppressedProviderIsNeverTracked() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        let appeared = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 777,
            suppressedProviders: [.codex],
            now: start
        )
        #expect(appeared.isEmpty)
        #expect(estimator.nextDeadline == nil)
        #expect(estimator.fireDue(now: start.addingTimeInterval(30)).isEmpty)
        #expect(estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(30)
        ).isEmpty)
    }

    @Test("two sequential epochs on the same pane and pid get distinct run IDs")
    func sequentialEpochsGetDistinctRunIDs() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 888,
            suppressedProviders: [],
            now: start
        )
        let firstStarted = estimator.fireDue(now: start.addingTimeInterval(3))
        #expect(firstStarted.count == 1)
        _ = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(4)
        )
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: nil,
            processID: nil,
            suppressedProviders: [],
            now: start.addingTimeInterval(5)
        )

        // Same pid, reused by a second, unrelated launch.
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 888,
            suppressedProviders: [],
            now: start.addingTimeInterval(6)
        )
        let secondStarted = estimator.fireDue(now: start.addingTimeInterval(9))
        #expect(secondStarted.count == 1)

        #expect(firstStarted[0].runID != secondStarted[0].runID)
    }

    @Test("replaying the same input sequence on a fresh estimator reproduces the same event IDs")
    func replayIsIdempotent() {
        func run() -> [AgentEvent] {
            let estimator = NativeAgentRunEstimator(startGrace: 3)
            var events: [AgentEvent] = []
            events += estimator.providerChanged(
                surfaceID: surfaceID,
                provider: .codex,
                processID: 999,
                suppressedProviders: [],
                now: start
            )
            events += estimator.fireDue(now: start.addingTimeInterval(3))
            events += estimator.commandFinished(
                surfaceID: surfaceID,
                exitCode: 0,
                now: start.addingTimeInterval(10)
            )
            return events
        }

        let first = run()
        let second = run()
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.runID) == second.map(\.runID))
        #expect(!first.isEmpty)
    }

    @Test("an event carrying this estimator's own synthesized hookName does not mark the epoch hook-covered")
    func ownSyntheticHookNameDoesNotMarkHookCovered() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 1010,
            suppressedProviders: [],
            now: start
        )
        let started = estimator.fireDue(now: start.addingTimeInterval(3))
        #expect(started.count == 1)

        // Feed back the estimator's own started event, as the real pipeline
        // does (AppDelegate.receiveAgentEvent observes every event,
        // including synthesized ones).
        estimator.observeRealEvent(started[0])

        let finished = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(10)
        )
        #expect(finished.count == 1)
        #expect(finished[0].kind == .succeeded)
    }

    @Test("a real hook event after started hands ownership to the hook side")
    func realEventAfterStartedStopsFurtherEmission() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .claudeCode,
            processID: 1111,
            suppressedProviders: [],
            now: start
        )
        let started = estimator.fireDue(now: start.addingTimeInterval(3))
        #expect(started.count == 1)

        estimator.observeRealEvent(
            realHookEvent(provider: .claudeCode, kind: .running, hookName: "PostToolBatch")
        )

        let disappeared = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: nil,
            processID: nil,
            suppressedProviders: [],
            now: start.addingTimeInterval(10)
        )
        #expect(disappeared.isEmpty)
    }

    // MARK: - Turn mode (Phase 2: transcript-derived turns)

    @Test("a turn observation during pendingStart cancels the epoch-level start and enters turn mode directly")
    func turnHandoffFromPendingStart() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .claudeCode,
            processID: 2001,
            suppressedProviders: [],
            now: start
        )

        let events = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .active),
            now: start.addingTimeInterval(1)
        )
        #expect(events.count == 1)
        #expect(events[0].kind == .started)
        #expect(events[0].hookName == "mytty.native.turnStarted")
        #expect(events[0].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .claudeCode,
            runKey: "prompt-1"
        ))

        // The epoch-level start grace never fires -- transcript activity
        // already committed to a turn-mode `started`.
        #expect(estimator.nextDeadline == nil)
        #expect(estimator.fireDue(now: start.addingTimeInterval(10)).isEmpty)
    }

    @Test("a turn observation after the epoch already started parks the epoch run, then starts the turn run")
    func turnHandoffFromStarted() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 2002,
            suppressedProviders: [],
            now: start
        )
        let started = estimator.fireDue(now: start.addingTimeInterval(3))
        #expect(started.count == 1)
        let epochRunID = started[0].runID

        let events = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(4)
        )
        #expect(events.count == 2)
        #expect(events[0].kind == .idle)
        #expect(events[0].hookName == "mytty.native.turnHandoff")
        #expect(events[0].runID == epochRunID)
        #expect(events[1].kind == .started)
        #expect(events[1].hookName == "mytty.native.turnStarted")
        #expect(events[1].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .codex,
            runKey: "turn-1"
        ))
    }

    @Test("a completed turn succeeds on the turn's own run, aligned with hookAlignedRunID")
    func turnCompletes() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .claudeCode,
            processID: 2003,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .active),
            now: start.addingTimeInterval(1)
        )

        let events = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .completed),
            now: start.addingTimeInterval(5)
        )
        #expect(events.count == 1)
        #expect(events[0].kind == .succeeded)
        #expect(events[0].hookName == "mytty.native.turnCompleted")
        #expect(events[0].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .claudeCode,
            runKey: "prompt-1"
        ))

        // A repeated completion for the same (now inactive) turn is a no-op.
        #expect(estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .completed),
            now: start.addingTimeInterval(6)
        ).isEmpty)
    }

    @Test("observing the same active turn key again is a no-op")
    func sameActiveTurnKeyIsNoOp() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 2011,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(1)
        )
        let repeated = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(2)
        )
        #expect(repeated.isEmpty)
    }

    @Test("a new prompt starting before the previous one completed parks it, then starts the new turn")
    func turnSuperseded() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .claudeCode,
            processID: 2004,
            suppressedProviders: [],
            now: start
        )
        let firstStarted = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .active),
            now: start.addingTimeInterval(1)
        )
        #expect(firstStarted.count == 1)

        let events = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-2", phase: .active),
            now: start.addingTimeInterval(2)
        )
        #expect(events.count == 2)
        #expect(events[0].kind == .idle)
        #expect(events[0].hookName == "mytty.native.turnSuperseded")
        #expect(events[0].runID == firstStarted[0].runID)
        #expect(events[1].kind == .started)
        #expect(events[1].hookName == "mytty.native.turnStarted")
        #expect(events[1].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .claudeCode,
            runKey: "prompt-2"
        ))
    }

    @Test("an interrupted turn parks its own run and clears the active turn")
    func turnInterrupted() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 2005,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(1)
        )

        let events = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .interrupted),
            now: start.addingTimeInterval(2)
        )
        #expect(events.count == 1)
        #expect(events[0].kind == .idle)
        #expect(events[0].hookName == "mytty.native.turnInterrupted")
        #expect(events[0].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .codex,
            runKey: "turn-1"
        ))
    }

    @Test("the process finishing while a turn is active ends the turn's own run, not the epoch run")
    func processFinishedEndsActiveTurnRun() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 2006,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(1)
        )

        let finished = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(5)
        )
        #expect(finished.count == 1)
        #expect(finished[0].kind == .succeeded)
        #expect(finished[0].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .codex,
            runKey: "turn-1"
        ))
    }

    @Test("the process disappearing while a turn is active ends the turn's own run, not the epoch run")
    func processDisappearsEndsActiveTurnRun() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 2007,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(1)
        )

        let disappeared = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: nil,
            processID: nil,
            suppressedProviders: [],
            now: start.addingTimeInterval(5)
        )
        #expect(disappeared.count == 1)
        #expect(disappeared[0].kind == .disconnected)
        #expect(disappeared[0].runID == AgentHookEventAdapter.hookAlignedRunID(
            provider: .codex,
            runKey: "turn-1"
        ))
    }

    @Test("the process ending with no active turn emits nothing -- the epoch run was already parked")
    func processEndingWithNoActiveTurnEmitsNothing() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .codex,
            processID: 2008,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .active),
            now: start.addingTimeInterval(1)
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .codex,
            turn: AgentTurnObservation(key: "turn-1", phase: .completed),
            now: start.addingTimeInterval(2)
        )

        let finished = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(5)
        )
        #expect(finished.isEmpty)
    }

    @Test("a real hook event during turn mode stops all further estimation")
    func hookCoveredDuringTurnModeStopsEverything() {
        let estimator = NativeAgentRunEstimator(startGrace: 3)
        _ = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: .claudeCode,
            processID: 2009,
            suppressedProviders: [],
            now: start
        )
        _ = estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .active),
            now: start.addingTimeInterval(1)
        )

        estimator.observeRealEvent(
            realHookEvent(provider: .claudeCode, kind: .running, hookName: "PostToolBatch")
        )

        #expect(estimator.turnObserved(
            surfaceID: surfaceID,
            provider: .claudeCode,
            turn: AgentTurnObservation(key: "prompt-1", phase: .completed),
            now: start.addingTimeInterval(2)
        ).isEmpty)
        #expect(estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: 0,
            now: start.addingTimeInterval(3)
        ).isEmpty)
    }

    @Test("replaying the same turn-mode input sequence reproduces the same event IDs")
    func turnModeReplayIsIdempotent() {
        func run() -> [AgentEvent] {
            let estimator = NativeAgentRunEstimator(startGrace: 3)
            var events: [AgentEvent] = []
            events += estimator.providerChanged(
                surfaceID: surfaceID,
                provider: .claudeCode,
                processID: 2010,
                suppressedProviders: [],
                now: start
            )
            events += estimator.turnObserved(
                surfaceID: surfaceID,
                provider: .claudeCode,
                turn: AgentTurnObservation(key: "prompt-1", phase: .active),
                now: start.addingTimeInterval(1)
            )
            events += estimator.turnObserved(
                surfaceID: surfaceID,
                provider: .claudeCode,
                turn: AgentTurnObservation(key: "prompt-2", phase: .active),
                now: start.addingTimeInterval(2)
            )
            events += estimator.turnObserved(
                surfaceID: surfaceID,
                provider: .claudeCode,
                turn: AgentTurnObservation(key: "prompt-2", phase: .completed),
                now: start.addingTimeInterval(5)
            )
            return events
        }

        let first = run()
        let second = run()
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.runID) == second.map(\.runID))
        #expect(!first.isEmpty)
    }

    private func realHookEvent(
        provider: AgentProvider,
        kind: AgentEventKind,
        hookName: String
    ) -> AgentEvent {
        AgentEvent(
            runID: AgentRunID(rawValue: UUID(
                uuidString: "00000000-0000-0000-0000-000000000201"
            )!),
            surfaceID: surfaceID,
            provider: provider,
            kind: kind,
            occurredAt: start,
            hookName: hookName
        )
    }
}
