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
public struct AgentJobTracker: Equatable, Sendable {
    public let jobID: AgentJobID
    public let paneID: TerminalSurfaceID
    public let provider: AgentWorkerProvider
    public let label: String?
    public let createdAt: Date
    public let launchDeadline: Date
    private let baselineRunIDs: Set<AgentRunID>
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

        let eligible = matchingRuns.filter {
            !baselineRunIDs.contains($0.id)
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
    /// poll to the next.
    private static func selectCandidate(_ runs: [AgentRun]) -> AgentRun? {
        runs.min { lhs, rhs in
            let lhsStarted = lhs.startedAt ?? .distantPast
            let rhsStarted = rhs.startedAt ?? .distantPast
            if lhsStarted != rhsStarted { return lhsStarted < rhsStarted }
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
