import Foundation
import MyTTYCore

/// A pane agent's own `mytty-ctl status` self-report ("running tests").
/// Deliberately not an `AgentEvent`: it changes no run state, must never
/// be persisted, and doesn't come from a hook — see
/// `docs/explanation/mytty-ctl-architecture.md`.
struct PaneStatusNote: Equatable {
    let text: String
    let updatedAt: Date
}

@MainActor
final class AttentionCenter: ObservableObject {
    @Published private(set) var items: [AttentionItem] = []
    @Published private(set) var runs: [AgentRunID: AgentRun] = [:]
    /// In-memory only, keyed by pane. Not touched by `reload()`'s full
    /// re-reduce, and gone after an app restart — matching the ephemeral
    /// contract `mytty-ctl status` documents.
    @Published private(set) var paneStatusNotes:
        [TerminalSurfaceID: PaneStatusNote] = [:]

    private let repository: SQLiteAgentEventRepository
    private let policy: AttentionPolicy
    private var events: [AgentEvent] = []
    private var acknowledgements: [AttentionAcknowledgement] = []

    init(
        repository: SQLiteAgentEventRepository,
        policy: AttentionPolicy = AttentionPolicy()
    ) {
        self.repository = repository
        self.policy = policy
    }

    @discardableResult
    func append(_ event: AgentEvent) throws -> Bool {
        let inserted = try repository.append(event)
        if inserted {
            expireStatusNote(for: event)
            try reload()
        }
        return inserted
    }

    func setStatusNote(
        _ text: String,
        for surfaceID: TerminalSurfaceID,
        at updatedAt: Date = Date()
    ) {
        paneStatusNotes[surfaceID] = PaneStatusNote(
            text: text,
            updatedAt: updatedAt
        )
    }

    func clearStatusNote(for surfaceID: TerminalSurfaceID) {
        paneStatusNotes[surfaceID] = nil
    }

    func statusNote(for surfaceID: TerminalSurfaceID) -> String? {
        paneStatusNotes[surfaceID]?.text
    }

    /// A run starting or ending obsoletes whatever the pane's agent last
    /// self-reported — "running tests" must not outlive the run it
    /// described, and a fresh run must not inherit the previous one's
    /// note. Mid-run transitions (`running`, `input-requested`,
    /// `approval-requested`) keep the note: the reported activity is
    /// still the one in progress.
    private func expireStatusNote(for event: AgentEvent) {
        switch event.kind {
        case .idle, .started, .succeeded, .failed, .disconnected:
            clearStatusNote(for: event.surfaceID)
        case .running, .inputRequested, .approvalRequested:
            break
        }
    }

    func acknowledge(_ item: AttentionItem) throws {
        _ = try repository.acknowledge(
            eventID: item.id,
            at: Date()
        )
        try reload()
    }

    @discardableResult
    func acknowledgeActionableItems(
        for surfaceID: TerminalSurfaceID,
        at acknowledgedAt: Date = Date()
    ) throws -> Int {
        try acknowledgeActionableItems(
            for: [surfaceID],
            at: acknowledgedAt
        )
    }

    /// Acknowledges every actionable item on the given surfaces in one
    /// pass with a single reload — closing a pane, tab, or window must
    /// not leave unread items behind for surfaces that no longer exist.
    @discardableResult
    func acknowledgeActionableItems(
        for surfaceIDs: [TerminalSurfaceID],
        at acknowledgedAt: Date = Date()
    ) throws -> Int {
        let identifiers = Set(surfaceIDs)
        let matchingItems = items.filter {
            identifiers.contains($0.surfaceID) && $0.isActionable
        }
        guard !matchingItems.isEmpty else { return 0 }

        var acknowledgedCount = 0
        for item in matchingItems {
            if try repository.acknowledge(
                eventID: item.id,
                at: acknowledgedAt
            ) {
                acknowledgedCount += 1
            }
        }
        if acknowledgedCount > 0 {
            try reload(now: acknowledgedAt)
        }
        return acknowledgedCount
    }

    /// Acknowledges completion items that predate `cutoff`. Events only
    /// flow while Mytty runs, so at launch every stored completion comes
    /// from an earlier run the user already lived through — without this
    /// sweep they would all resurface as unread. Approval/input requests
    /// and failures are kept: those may still describe something worth
    /// following up on.
    @discardableResult
    func acknowledgeCompletions(
        before cutoff: Date,
        at acknowledgedAt: Date = Date()
    ) throws -> Int {
        let staleCompletions = items.filter {
            $0.kind == .completion && $0.isActionable
                && $0.createdAt < cutoff
        }
        guard !staleCompletions.isEmpty else { return 0 }

        var acknowledgedCount = 0
        for item in staleCompletions {
            if try repository.acknowledge(
                eventID: item.id,
                at: acknowledgedAt
            ) {
                acknowledgedCount += 1
            }
        }
        if acknowledgedCount > 0 {
            try reload(now: acknowledgedAt)
        }
        return acknowledgedCount
    }

    /// Acknowledges every actionable item at once — the drawer's
    /// clear-all action.
    @discardableResult
    func acknowledgeAllActionableItems(
        at acknowledgedAt: Date = Date()
    ) throws -> Int {
        let actionableItems = items.filter(\.isActionable)
        guard !actionableItems.isEmpty else { return 0 }

        var acknowledgedCount = 0
        for item in actionableItems {
            if try repository.acknowledge(
                eventID: item.id,
                at: acknowledgedAt
            ) {
                acknowledgedCount += 1
            }
        }
        if acknowledgedCount > 0 {
            try reload(now: acknowledgedAt)
        }
        return acknowledgedCount
    }

    /// Closes out any run the replayed log still shows as non-terminal --
    /// every pane process dies with the app, so a run left
    /// `running`/`waitingInput`/`waitingApproval` after a crash,
    /// force-quit, or SIGKILL can only be dead. Call once at startup, right
    /// after `reload()`, before windows restore, so the status bar never
    /// shows a phantom active agent for a session that can't exist
    /// anymore. Persists each sweep event directly through `repository`
    /// rather than the normal `append(_:)` path, then reloads once at the
    /// end -- with a stale-run count in the hundreds (a first launch after
    /// this sweep shipped, or a long-neglected log), `append(_:)`'s
    /// per-call `reload()` would replay the entire event log once per
    /// stale run instead of once total. It's idempotent the same way any
    /// other event is: a second sweep of an already-swept run finds it
    /// already terminal and its deterministic event ID already recorded,
    /// so `repository.append` reports no insertion for it.
    func sweepInterruptedRuns(now: Date = Date()) throws {
        let staleRuns = AgentHookEventAdapter.runsNeedingStartupSweep(
            Array(runs.values)
        )
        guard !staleRuns.isEmpty else { return }

        var insertedAny = false
        for run in staleRuns {
            let event = AgentHookEventAdapter.startupSweepEvent(
                run: run,
                occurredAt: now
            )
            if try repository.append(event) {
                expireStatusNote(for: event)
                insertedAny = true
            }
        }
        if insertedAny {
            try reload(now: now)
        }
    }

    func reload(now: Date = Date()) throws {
        events = try repository.loadEvents()
        acknowledgements = try repository.loadAcknowledgements()
        runs = AgentEventReducer.reduce(events)
        items = AttentionReducer.reduce(
            events: events,
            acknowledgements: acknowledgements,
            now: now,
            policy: policy
        )
    }

    var actionableCount: Int {
        items.lazy.filter(\.isActionable).count
    }

    func actionableCount(for surfaceIDs: [TerminalSurfaceID]) -> Int {
        let identifiers = Set(surfaceIDs)
        return items.lazy.filter {
            $0.isActionable && identifiers.contains($0.surfaceID)
        }.count
    }

    func mostRelevantState(
        for surfaceIDs: [TerminalSurfaceID]
    ) -> AgentRunState? {
        mostRelevantRun(for: Set(surfaceIDs))?.state
    }

    func mostRelevantRun(for surfaceID: TerminalSurfaceID) -> AgentRun? {
        mostRelevantRun(for: [surfaceID])
    }

    func latestRun(
        for surfaceID: TerminalSurfaceID,
        provider: AgentProvider
    ) -> AgentRun? {
        runs.values
            .filter {
                $0.surfaceID == surfaceID && $0.provider == provider
            }
            .max(by: terminalRunIsOlder)
    }

    /// Every tracked run for `surfaceID`/`provider`, unfiltered by
    /// relevance or recency — the narrow read `AgentJobTracker.reconcile`
    /// needs to bind a job to the exact run it spawned. Deliberately not
    /// `mostRelevantRun`/`latestRun`: those are tuned for "what should the
    /// status bar show," which can disagree with "which run does this
    /// specific job own." Returns snapshots (`AgentRun` is a value type),
    /// not a reference into `runs`, so callers can't mutate tracked state.
    func runs(
        forPane surfaceID: TerminalSurfaceID,
        provider: AgentProvider
    ) -> [AgentRun] {
        runs.values.filter {
            $0.surfaceID == surfaceID && $0.provider == provider
        }
    }

    private func mostRelevantRun(
        for surfaceIDs: Set<TerminalSurfaceID>
    ) -> AgentRun? {
        let matchingRuns = runs.values
            .filter { surfaceIDs.contains($0.surfaceID) }
        let activeRuns = matchingRuns.filter { isActive($0.state) }
        if let active = activeRuns.max(by: activeRunIsLessRelevant) {
            return active
        }
        return matchingRuns.max(by: terminalRunIsOlder)
    }

    func activeProvider(
        for surfaceID: TerminalSurfaceID
    ) -> AgentProvider? {
        runs.values
            .filter {
                $0.surfaceID == surfaceID && isActive($0.state)
            }
            .max(by: activeRunIsLessRelevant)?
            .provider
    }

    private func isActive(_ state: AgentRunState) -> Bool {
        switch state {
        case .running, .waitingInput, .waitingApproval:
            true
        case .unknown, .idle, .succeeded, .failed, .disconnected:
            false
        }
    }

    private func activeRunIsLessRelevant(_ lhs: AgentRun, _ rhs: AgentRun) -> Bool {
        let lhsPriority = statePriority(lhs.state)
        let rhsPriority = statePriority(rhs.state)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return updatedAt(lhs) < updatedAt(rhs)
    }

    private func terminalRunIsOlder(_ lhs: AgentRun, _ rhs: AgentRun) -> Bool {
        let lhsDate = updatedAt(lhs)
        let rhsDate = updatedAt(rhs)
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return statePriority(lhs.state) < statePriority(rhs.state)
    }

    private func updatedAt(_ run: AgentRun) -> Date {
        run.updatedAt ?? .distantPast
    }

    private func statePriority(_ state: AgentRunState) -> Int {
        switch state {
        case .waitingApproval: 7
        case .waitingInput: 6
        case .failed: 5
        case .disconnected: 4
        case .running: 3
        case .succeeded: 2
        case .unknown, .idle: 1
        }
    }
}
