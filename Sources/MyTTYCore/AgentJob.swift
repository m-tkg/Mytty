import Foundation

/// Wire/domain model for the `mytty-ctl agent` orchestration API — the
/// high-level counterpart to the low-level pane commands in
/// `ControlProtocol.swift`. See `docs/reference/mytty-ctl.md` and
/// `docs/explanation/mytty-ctl-architecture.md`.
///
/// A job is tracked only in `MyTTYApp` memory (`AgentJobCoordinator`), never
/// persisted: it identifies one spawn of one worker pane so an orchestrator
/// can wait on and address that exact run, as opposed to whatever a pane
/// happens to be doing when it's polled. App restart makes previously
/// issued job IDs unavailable; the panes/processes they pointed at are
/// unaffected.
public struct AgentJobID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

public enum AgentWorkerProvider: String, Codable, Equatable, Sendable {
    case codex
    case claude
    case cursor

    /// The corresponding hook-integration/event provider this worker
    /// reports as, once launched — used to look up integration status and
    /// to match `AgentRun`s to this job's pane.
    public var agentProvider: AgentProvider {
        switch self {
        case .codex: .codex
        case .claude: .claudeCode
        case .cursor: .cursor
        }
    }
}

public enum AgentAccessPolicy: String, Codable, Equatable, Sendable {
    case review
    case workspaceWrite = "workspace-write"
    /// Copy the lead's own mode flags onto the worker instead of using a
    /// fixed access-derived flag set — only valid when the worker is the
    /// same provider as the pane spawning it. `AgentJobCoordinator`
    /// resolves this to `.workspaceWrite` (with no inherited flags) before
    /// it ever reaches `AgentLaunchPlan` if the lead is running in its
    /// default mode; see `AgentModeInheritance`.
    case inherit
}

public enum AgentJobState: String, Codable, Equatable, Sendable {
    case launching
    case running
    case waitingInput = "waiting-input"
    case waitingApproval = "waiting-approval"
    case succeeded
    case failed
    case disconnected
    case launchFailed = "launch-failed"
    case lost

    /// States `agent wait --until completed` resolves on. A job that never
    /// bound to a run (`launchFailed`) or whose pane vanished (`lost`) is
    /// "completed" in the sense that it will never produce more output —
    /// an orchestrator waiting on it should stop waiting either way.
    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .disconnected, .launchFailed, .lost:
            true
        case .launching, .running, .waitingInput, .waitingApproval:
            false
        }
    }

    public func satisfies(_ condition: AgentWaitCondition) -> Bool {
        switch condition {
        case .running:
            self != .launching
        case .attention:
            self == .waitingInput || self == .waitingApproval
        case .completed:
            isTerminal
        }
    }
}

public enum AgentWaitCondition: String, Codable, Equatable, Sendable {
    case running
    case attention
    case completed
}

public struct AgentJobSnapshot: Codable, Equatable, Sendable {
    public let jobID: AgentJobID
    public let paneID: TerminalSurfaceID
    public let provider: AgentWorkerProvider
    public let label: String?
    public let state: AgentJobState
    public let runID: AgentRunID?
    public let sessionID: String?
    public let message: String?

    public init(
        jobID: AgentJobID,
        paneID: TerminalSurfaceID,
        provider: AgentWorkerProvider,
        label: String?,
        state: AgentJobState,
        runID: AgentRunID?,
        sessionID: String?,
        message: String?
    ) {
        self.jobID = jobID
        self.paneID = paneID
        self.provider = provider
        self.label = label
        self.state = state
        self.runID = runID
        self.sessionID = sessionID
        self.message = message
    }
}

/// Maps the provider integration status Mytty already tracks in Settings
/// onto the `agent spawn` preflight failure codes. Pure and tiny on
/// purpose: it's the one bit of `AgentJobCoordinator`'s preflight logic
/// that's worth pulling out of app glue so it stays covered by a fast unit
/// test independent of `AppDelegate`/`AgentIntegrationSettingsModel` wiring.
public enum AgentIntegrationPreflight {
    public static func failureCode(
        for status: AgentIntegrationStatus
    ) -> String? {
        switch status {
        case .notInstalled: "provider-integration-not-installed"
        case .needsRepair: "provider-integration-needs-repair"
        case .installed: nil
        }
    }
}

/// Pure job/run reconciliation. One `AgentJobTracker` tracks exactly one
/// job's lifecycle from `spawn` onward; `AgentJobCoordinator` (MyTTYApp)
/// owns a `[AgentJobID: AgentJobTracker]` registry and calls `reconcile`
/// with a fresh read of `AttentionCenter` on every `wait`/`result`/etc.
/// poll. `reconcile` never reads global state itself, which is what makes
/// the binding rules here independently testable:
///
/// 1. Once bound to a run, only that run may update the job.
/// 2. Otherwise, a run only becomes a *candidate* if its pane/provider
///    match and its run ID wasn't already present when the job was
///    created (the `baselineRunIDs` captured at spawn time) — this is what
///    stops a job from binding to a run that predates it.
/// 3. Multiple simultaneous candidates are resolved deterministically by
///    `startedAt`, then `updatedAt`, then run-ID string, so two jobs
///    spawned back to back never race for the same run.
/// 4. `AgentRunState` maps onto `AgentJobState` directly — never through
///    `AttentionCenter.mostRelevantRun`, which is tuned for "what should
///    the status bar show" rather than "which exact run is this job's".
/// 5. A job never rebinds to a different run once bound.
/// 6. A pane disappearing transitions a nonterminal job to `.lost`.
/// 7. No candidate binding before `launchDeadline` transitions the job to
///    `.launchFailed`.
/// 8. Rule 5 is what stops a job from being confused about *which* run
///    it's tracking, not a promise that a job can only ever track one
///    run for its whole lifetime. `prepareForFollowUp` is the one
///    deliberate, orchestrator-triggered exception: once the bound run
///    has finished (`.succeeded`/`.failed`/`.disconnected`), it re-arms
///    the job for a brand new run — see that method's documentation.
public struct AgentJobTracker: Equatable, Sendable {
    public let jobID: AgentJobID
    public let paneID: TerminalSurfaceID
    public let provider: AgentWorkerProvider
    public let label: String?
    public let createdAt: Date
    public private(set) var launchDeadline: Date
    private var baselineRunIDs: Set<AgentRunID>
    public private(set) var boundRunID: AgentRunID?
    public private(set) var state: AgentJobState
    public private(set) var sessionID: String?
    public private(set) var message: String?

    public init(
        jobID: AgentJobID = AgentJobID(),
        paneID: TerminalSurfaceID,
        provider: AgentWorkerProvider,
        label: String?,
        baselineRunIDs: Set<AgentRunID>,
        createdAt: Date,
        launchWindow: TimeInterval = 30
    ) {
        self.jobID = jobID
        self.paneID = paneID
        self.provider = provider
        self.label = label
        self.baselineRunIDs = baselineRunIDs
        self.createdAt = createdAt
        launchDeadline = createdAt.addingTimeInterval(launchWindow)
        boundRunID = nil
        state = .launching
        sessionID = nil
        message = nil
    }

    public var snapshot: AgentJobSnapshot {
        AgentJobSnapshot(
            jobID: jobID,
            paneID: paneID,
            provider: provider,
            label: label,
            state: state,
            runID: boundRunID,
            sessionID: sessionID,
            message: message
        )
    }

    /// Advances tracked state from a fresh read of the runs currently known
    /// for this job's pane, and whether the pane still exists. `runs` need
    /// not be pre-filtered by the caller — pane/provider matching happens
    /// here too, so this stays testable and correct on its own.
    public mutating func reconcile(
        runs: [AgentRun],
        paneExists: Bool,
        now: Date
    ) {
        guard paneExists else {
            if !state.isTerminal {
                state = .lost
            }
            return
        }

        let matchingRuns = runs.filter {
            $0.surfaceID == paneID && $0.provider == provider.agentProvider
        }

        if let boundRunID {
            guard let boundRun = matchingRuns.first(where: {
                $0.id == boundRunID
            }) else {
                // The bound run isn't in this snapshot (e.g. a caller
                // passed a partial/stale list). Never fall back to a
                // different run — rule 5 — so just keep the last known
                // state until a snapshot containing it arrives again.
                return
            }
            apply(boundRun)
            return
        }

        guard state != .launchFailed else {
            // The launch deadline already passed and nothing bound in
            // time; a late-arriving run must not resurrect the job (rule
            // 7 is a one-way door, otherwise a slow-to-report provider
            // could un-fail a job the orchestrator already gave up on).
            return
        }

        // A single provider launch can produce more than one runID: Codex
        // and Claude Code both fire a `SessionStart` hook as its own
        // `idle`-kind event before the real work run's `UserPromptSubmit`/
        // `started` event arrives, and the reducer gives that marker its
        // own runID rather than folding it into the run that follows
        // (confirmed against a live Codex spawn during manual testing —
        // see AgentJobTrackerTests for the reproduction). A run stuck at
        // `.unknown`/`.idle` never advances, so binding to it would
        // permanently strand the job below `.launching` while the real
        // run it should be tracking succeeds unnoticed. Only a run that
        // has actually progressed is eligible to bind.
        let eligible = matchingRuns.filter {
            !baselineRunIDs.contains($0.id)
                && $0.state != .unknown && $0.state != .idle
        }
        if let winner = Self.selectCandidate(eligible) {
            boundRunID = winner.id
            apply(winner)
            return
        }

        if now >= launchDeadline {
            state = .launchFailed
            message = "No \(provider.rawValue) run was observed within "
                + "the launch window after spawning."
        }
    }

    /// States a bound run must have reached for `prepareForFollowUp` to
    /// rebind. Deliberately narrower than `AgentJobState.isTerminal`:
    /// `.launchFailed` means no run ever bound (there's nothing to
    /// "finish" and send a follow-up to), and `.lost` means the pane
    /// itself is gone (a follow-up couldn't be delivered anyway) — both
    /// stay untouched here rather than silently re-arming a job that
    /// isn't in a state a follow-up makes sense for.
    private static let followUpEligibleStates: Set<AgentJobState> = [
        .succeeded, .failed, .disconnected,
    ]

    /// Called when `agent send` is about to deliver follow-up input to
    /// this job. Rule 5 (a job never rebinds once bound) exists to stop a
    /// *stale* run from being mistaken for the job's current one — it was
    /// never meant to make a job permanently unable to track a follow-up
    /// the orchestrator deliberately asked for. Without this, `agent
    /// wait --until completed` after a follow-up `agent send` resolves
    /// immediately against the *previous* run's already-terminal state,
    /// which is the bug this exists to fix (reproduced against the real
    /// app: a follow-up send followed immediately by `wait` returned the
    /// prior run's `succeeded` without ever looking at the new one).
    ///
    /// If the bound run already reached one of `followUpEligibleStates`,
    /// this releases the bind and re-arms the job exactly as it was right
    /// after `spawn`: the baseline resets to `knownRunIDs` (everything
    /// visible for this pane *right now*, including the just-finished
    /// run, so it can never bind again — rule 2), state goes back to
    /// `.launching`, and `launchDeadline` is pushed out by `launchWindow`
    /// from `now` so a follow-up that never gets picked up still
    /// eventually resolves to `.launchFailed` (rule 7) instead of hanging
    /// forever.
    ///
    /// If the bound run is still active (or there is no bound run yet —
    /// still `.launching`), this is a no-op: the input is just delivered
    /// into the ongoing run, same as before this method existed.
    ///
    /// Returns whether a rebind window was (re)armed.
    @discardableResult
    public mutating func prepareForFollowUp(
        knownRunIDs: Set<AgentRunID>,
        now: Date,
        launchWindow: TimeInterval = 30
    ) -> Bool {
        guard Self.followUpEligibleStates.contains(state) else {
            return false
        }
        baselineRunIDs = knownRunIDs
        boundRunID = nil
        state = .launching
        launchDeadline = now.addingTimeInterval(launchWindow)
        return true
    }

    private mutating func apply(_ run: AgentRun) {
        state = Self.map(run.state)
        if let runSessionID = run.sessionID {
            sessionID = runSessionID
        }
        if let runMessage = run.message {
            message = runMessage
        }
    }

    /// Earliest `startedAt`, then earliest `updatedAt`, then the
    /// lexicographically smallest run-ID string — arbitrary but stable, so
    /// two jobs racing to bind never land on inconsistent choices from one
    /// poll to the next. A run that never reached `.running` (so has no
    /// `startedAt` — e.g. one that disconnected while still `.unknown`)
    /// always loses to one that did, regardless of the raw timestamp
    /// values: `nil` must never be treated as "earliest" here, since that
    /// would make an event that never really started outrank one that
    /// demonstrably did.
    private static func selectCandidate(_ runs: [AgentRun]) -> AgentRun? {
        runs.min { lhs, rhs in
            switch (lhs.startedAt, rhs.startedAt) {
            case let (lhsStarted?, rhsStarted?):
                if lhsStarted != rhsStarted { return lhsStarted < rhsStarted }
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                break
            }
            let lhsUpdated = lhs.updatedAt ?? .distantPast
            let rhsUpdated = rhs.updatedAt ?? .distantPast
            if lhsUpdated != rhsUpdated { return lhsUpdated < rhsUpdated }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    private static func map(_ runState: AgentRunState) -> AgentJobState {
        switch runState {
        case .unknown, .idle: .launching
        case .running: .running
        case .waitingInput: .waitingInput
        case .waitingApproval: .waitingApproval
        case .succeeded: .succeeded
        case .failed: .failed
        case .disconnected: .disconnected
        }
    }
}
