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
