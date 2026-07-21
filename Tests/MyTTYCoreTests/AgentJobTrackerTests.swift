import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent job tracker")
struct AgentJobTrackerTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("starts in launching, unbound, before any reconcile")
    func startsInLaunching() {
        let paneID = TerminalSurfaceID()
        let tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: "investigation-a",
            baselineRunIDs: [],
            createdAt: base
        )
        #expect(tracker.state == .launching)
        #expect(tracker.boundRunID == nil)
        #expect(tracker.snapshot.state == .launching)
        #expect(tracker.snapshot.label == "investigation-a")
        #expect(tracker.snapshot.paneID == paneID)
    }

    @Test("ignores a run that already existed when the job was created")
    func ignoresBaselineRunID() {
        let paneID = TerminalSurfaceID()
        let staleRunID = AgentRunID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [staleRunID],
            createdAt: base
        )
        let staleRun = makeRun(
            runID: staleRunID,
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base)]
        )
        tracker.reconcile(
            runs: [staleRun],
            paneExists: true,
            now: base.addingTimeInterval(1)
        )
        #expect(tracker.boundRunID == nil)
        #expect(tracker.state == .launching)
    }

    @Test("binds to a new run matching this job's pane and provider")
    func bindsNewMatchingRun() {
        let paneID = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )
        let run = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(1))]
        )
        tracker.reconcile(
            runs: [run],
            paneExists: true,
            now: base.addingTimeInterval(2)
        )
        #expect(tracker.boundRunID == run.id)
        #expect(tracker.state == .running)
        #expect(tracker.snapshot.runID == run.id)
    }

    @Test("ignores a run for a different pane or provider")
    func ignoresOtherPaneOrProvider() {
        let paneID = TerminalSurfaceID()
        let otherPane = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )
        let otherPaneRun = makeRun(
            surfaceID: otherPane,
            provider: .codex,
            kinds: [(.started, base)]
        )
        let otherProviderRun = makeRun(
            surfaceID: paneID,
            provider: .claudeCode,
            kinds: [(.started, base)]
        )
        tracker.reconcile(
            runs: [otherPaneRun, otherProviderRun],
            paneExists: true,
            now: base.addingTimeInterval(1)
        )
        #expect(tracker.boundRunID == nil)
        #expect(tracker.state == .launching)
    }

    @Test("deterministically picks the earliest-started eligible candidate")
    func deterministicCandidateSelection() {
        let paneID = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )
        let later = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(5))]
        )
        let earlier = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(1))]
        )
        tracker.reconcile(
            runs: [later, earlier],
            paneExists: true,
            now: base.addingTimeInterval(6)
        )
        #expect(tracker.boundRunID == earlier.id)
    }

    @Test("never rebinds to a different run once bound")
    func neverRebinds() {
        let paneID = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )
        let first = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(1))]
        )
        tracker.reconcile(
            runs: [first],
            paneExists: true,
            now: base.addingTimeInterval(2)
        )
        #expect(tracker.boundRunID == first.id)

        // An even-earlier-started run shows up in the same snapshot as the
        // already-bound one; the earlier-wins tie-break must never apply
        // once a job has bound.
        let second = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base)]
        )
        tracker.reconcile(
            runs: [first, second],
            paneExists: true,
            now: base.addingTimeInterval(3)
        )
        #expect(tracker.boundRunID == first.id)
    }

    @Test("maps the bound run's state through running, attention, and a terminal state")
    func mapsRunningAttentionAndTerminalStates() {
        let paneID = TerminalSurfaceID()
        let runID = AgentRunID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )

        let running = makeRun(
            runID: runID,
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base)]
        )
        tracker.reconcile(
            runs: [running],
            paneExists: true,
            now: base.addingTimeInterval(1)
        )
        #expect(tracker.state == .running)
        #expect(tracker.state.satisfies(.running))
        #expect(!tracker.state.satisfies(.attention))
        #expect(!tracker.state.satisfies(.completed))

        let waitingApproval = makeRun(
            runID: runID,
            surfaceID: paneID,
            provider: .codex,
            kinds: [
                (.started, base),
                (.approvalRequested, base.addingTimeInterval(1)),
            ]
        )
        tracker.reconcile(
            runs: [waitingApproval],
            paneExists: true,
            now: base.addingTimeInterval(2)
        )
        #expect(tracker.state == .waitingApproval)
        #expect(tracker.state.satisfies(.attention))
        #expect(tracker.state.satisfies(.running))
        #expect(!tracker.state.satisfies(.completed))

        let succeeded = makeRun(
            runID: runID,
            surfaceID: paneID,
            provider: .codex,
            kinds: [
                (.started, base),
                (.approvalRequested, base.addingTimeInterval(1)),
                (.running, base.addingTimeInterval(2)),
                (.succeeded, base.addingTimeInterval(3)),
            ]
        )
        tracker.reconcile(
            runs: [succeeded],
            paneExists: true,
            now: base.addingTimeInterval(4)
        )
        #expect(tracker.state == .succeeded)
        #expect(tracker.state.satisfies(.completed))
        #expect(tracker.state.satisfies(.running))
        #expect(!tracker.state.satisfies(.attention))
    }

    @Test("transitions to launch-failed once the deadline passes unbound")
    func launchDeadlineExceeded() {
        let paneID = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base,
            launchWindow: 30
        )
        tracker.reconcile(
            runs: [],
            paneExists: true,
            now: base.addingTimeInterval(29)
        )
        #expect(tracker.state == .launching)

        tracker.reconcile(
            runs: [],
            paneExists: true,
            now: base.addingTimeInterval(30)
        )
        #expect(tracker.state == .launchFailed)
        #expect(tracker.message != nil)
        #expect(tracker.state.satisfies(.completed))
    }

    @Test("ignores a run that arrives after the launch deadline already failed the job")
    func ignoresLateRunAfterLaunchFailed() {
        let paneID = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base,
            launchWindow: 30
        )
        tracker.reconcile(
            runs: [],
            paneExists: true,
            now: base.addingTimeInterval(30)
        )
        #expect(tracker.state == .launchFailed)

        let lateRun = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(31))]
        )
        tracker.reconcile(
            runs: [lateRun],
            paneExists: true,
            now: base.addingTimeInterval(32)
        )
        #expect(tracker.boundRunID == nil)
        #expect(tracker.state == .launchFailed)
    }

    @Test("transitions a nonterminal job to lost when its pane disappears")
    func disappearedPaneBecomesLost() {
        let paneID = TerminalSurfaceID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )
        let run = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base)]
        )
        tracker.reconcile(
            runs: [run],
            paneExists: true,
            now: base.addingTimeInterval(1)
        )
        #expect(tracker.state == .running)

        tracker.reconcile(
            runs: [run],
            paneExists: false,
            now: base.addingTimeInterval(2)
        )
        #expect(tracker.state == .lost)
        #expect(tracker.state.satisfies(.completed))
    }

    @Test("does not downgrade an already-terminal job when its pane disappears")
    func terminalJobStaysTerminalWhenPaneDisappears() {
        let paneID = TerminalSurfaceID()
        let runID = AgentRunID()
        var tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: base
        )
        let succeeded = makeRun(
            runID: runID,
            surfaceID: paneID,
            provider: .codex,
            kinds: [
                (.started, base),
                (.succeeded, base.addingTimeInterval(1)),
            ]
        )
        tracker.reconcile(
            runs: [succeeded],
            paneExists: true,
            now: base.addingTimeInterval(2)
        )
        #expect(tracker.state == .succeeded)

        tracker.reconcile(
            runs: [succeeded],
            paneExists: false,
            now: base.addingTimeInterval(3)
        )
        #expect(tracker.state == .succeeded)
    }

    @Test("two jobs spawned concurrently for the same pane/provider never cross-bind")
    func twoConcurrentJobsNeverCrossBind() {
        let paneID = TerminalSurfaceID()
        // Job A is created first; its baseline already contains no runs.
        var jobA = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: "a",
            baselineRunIDs: [],
            createdAt: base
        )
        // Job B is created a moment later, after job A's run has already
        // started -- its baseline captures that run, so it must never bind
        // to it even though it matches pane and provider.
        let runA = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(1))]
        )
        var jobB = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: "b",
            baselineRunIDs: [runA.id],
            createdAt: base.addingTimeInterval(2)
        )
        let runB = makeRun(
            surfaceID: paneID,
            provider: .codex,
            kinds: [(.started, base.addingTimeInterval(3))]
        )

        // Both jobs reconcile against the same shared view of every run
        // known for this pane/provider -- the real-world shape, since
        // `AttentionCenter` has no notion of "which job asked."
        let allRuns = [runA, runB]
        jobA.reconcile(
            runs: allRuns,
            paneExists: true,
            now: base.addingTimeInterval(4)
        )
        jobB.reconcile(
            runs: allRuns,
            paneExists: true,
            now: base.addingTimeInterval(4)
        )

        #expect(jobA.boundRunID == runA.id)
        #expect(jobB.boundRunID == runB.id)
    }

    // MARK: - Helpers

    /// Builds an `AgentRun` the same way production code does — by
    /// replaying `AgentEvent`s through the real reducer — since `AgentRun`
    /// has no public memberwise initializer outside `AgentEvent.swift`.
    private func makeRun(
        runID: AgentRunID = AgentRunID(),
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        kinds: [(AgentEventKind, Date)]
    ) -> AgentRun {
        let events = kinds.map { kind, date in
            AgentEvent(
                runID: runID,
                surfaceID: surfaceID,
                provider: provider,
                kind: kind,
                occurredAt: date
            )
        }
        let runs = AgentEventReducer.reduce(events)
        guard let run = runs[runID] else {
            fatalError("reducer did not produce a run for \(runID)")
        }
        return run
    }
}
