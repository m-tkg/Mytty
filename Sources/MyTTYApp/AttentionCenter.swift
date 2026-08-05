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
    private var pruneTimer: Timer?
    private static let pruneInterval: TimeInterval = 60 * 60

    init(
        repository: SQLiteAgentEventRepository,
        policy: AttentionPolicy = AttentionPolicy()
    ) {
        self.repository = repository
        self.policy = policy
    }

    /// Persists `event`, then updates `runs`/`items` by replaying the
    /// in-memory `events`/`acknowledgements` arrays rather than reloading
    /// from disk. `reload()` is a full `SQLiteAgentEventRepository
    /// .loadEvents()` — every row read back and JSON-decoded — which made
    /// every hook-delivered event this expensive to record; `events` here
    /// already holds everything on disk (kept current by `reload()` at
    /// startup and by every append/acknowledge since), so appending one
    /// more event and re-running the same pure reducers over memory is the
    /// only cost.
    @discardableResult
    func append(_ event: AgentEvent) throws -> Bool {
        let inserted = try repository.append(event)
        if inserted {
            expireStatusNote(for: event)
            events.append(event)
            let now = Date()
            recompute(now: now)
            // The event that just landed may have carried its run into a
            // terminal state -- that's the cheapest moment to prune,
            // since it's already paying for a recompute and needs no
            // extra scan to find candidates beyond the one `prune(now:)`
            // already does over `runs`. Most terminal transitions won't
            // actually prune anything yet (the 24h retention window is
            // rarely already elapsed), but this keeps a long-running
            // session's log from just waiting on the hourly timer.
            if let run = runs[event.runID], isTerminalRunState(run.state) {
                try prune(now: now)
            }
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
        let acknowledgedAt = Date()
        if try repository.acknowledge(
            eventID: item.id,
            at: acknowledgedAt
        ) {
            acknowledgements.append(
                AttentionAcknowledgement(
                    eventID: item.id,
                    acknowledgedAt: acknowledgedAt
                )
            )
        }
        // Recompute unconditionally, matching the pre-in-memory behavior
        // of always reloading: `now` advancing on its own can age a
        // resolved/acknowledged item out of `AttentionPolicy
        // .resolvedRetention` even when this particular call acknowledged
        // nothing new.
        recomputeItems(now: acknowledgedAt)
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
                acknowledgements.append(
                    AttentionAcknowledgement(
                        eventID: item.id,
                        acknowledgedAt: acknowledgedAt
                    )
                )
                acknowledgedCount += 1
            }
        }
        if acknowledgedCount > 0 {
            recomputeItems(now: acknowledgedAt)
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
                acknowledgements.append(
                    AttentionAcknowledgement(
                        eventID: item.id,
                        acknowledgedAt: acknowledgedAt
                    )
                )
                acknowledgedCount += 1
            }
        }
        if acknowledgedCount > 0 {
            recomputeItems(now: acknowledgedAt)
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
                acknowledgements.append(
                    AttentionAcknowledgement(
                        eventID: item.id,
                        acknowledgedAt: acknowledgedAt
                    )
                )
                acknowledgedCount += 1
            }
        }
        if acknowledgedCount > 0 {
            recomputeItems(now: acknowledgedAt)
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
    /// rather than the normal `append(_:)` path, appending it to the
    /// in-memory `events` too, and recomputes once at the end -- with a
    /// stale-run count in the hundreds (a first launch after this sweep
    /// shipped, or a long-neglected log), doing that per-run instead of
    /// once total would be needlessly repeated work even now that
    /// recomputing no longer touches disk. It's idempotent the same way
    /// any other event is: a second sweep of an already-swept run finds it
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
                events.append(event)
                insertedAny = true
            }
        }
        if insertedAny {
            recompute(now: now)
        }
    }

    /// Reloads `events`/`acknowledgements` from disk and recomputes
    /// `runs`/`items` from them. Full JSON-decode-every-row cost — reserve
    /// this for startup, where there's no in-memory state yet to update
    /// incrementally. Every other mutation (`append(_:)`, the
    /// `acknowledge*` family, `sweepInterruptedRuns`) keeps `events`/
    /// `acknowledgements` current itself and calls `recompute`/
    /// `recomputeItems` directly instead of reloading.
    func reload(now: Date = Date()) throws {
        events = try repository.loadEvents()
        acknowledgements = try repository.loadAcknowledgements()
        recompute(now: now)
    }

    /// Re-derives both `runs` and `items` from the in-memory `events`/
    /// `acknowledgements` arrays -- no disk access. Use after a change
    /// that can affect run state (a new event); an acknowledgement alone
    /// only ever changes `items`, so use `recomputeItems(now:)` there
    /// instead of paying for a redundant run replay.
    private func recompute(now: Date) {
        runs = AgentEventReducer.reduce(events)
        recomputeItems(now: now)
    }

    /// Re-derives `items` from the in-memory `events`/`acknowledgements`
    /// arrays, leaving `runs` untouched -- acknowledgements never change
    /// run state, and re-running `AgentEventReducer.reduce` on every
    /// acknowledgement would replay the whole event log for no reason.
    private func recomputeItems(now: Date) {
        items = AttentionReducer.reduce(
            events: events,
            acknowledgements: acknowledgements,
            now: now,
            policy: policy
        )
    }

    /// Deletes every event (and matching acknowledgement) belonging to a
    /// run that's "used up": terminal, with no actionable item left, and
    /// every relevant timestamp -- the run's own `updatedAt` and each of
    /// its items' resolved/acknowledged time -- older than
    /// `AttentionPolicy.resolvedRetention`. That mirrors the exact window
    /// the Inbox already uses to keep showing a resolved item, so this
    /// never deletes anything still visible there. Keeps the on-disk
    /// `agent_event` log from growing without bound (it's append-only
    /// otherwise), which is what let it reach 95k rows / 31MB before this
    /// existed. Deletes from `repository` first, then drops the same rows
    /// from `events`/`acknowledgements`/`runs`/`items` directly -- no
    /// disk reload needed, since the in-memory state was already
    /// authoritative for what got deleted.
    @discardableResult
    func prune(now: Date = Date()) throws -> Int {
        let staleRunIDs = prunableRunIDs(now: now)
        guard !staleRunIDs.isEmpty else { return 0 }

        let staleEventIDs = Set(
            events.filter { staleRunIDs.contains($0.runID) }.map(\.id)
        )
        guard !staleEventIDs.isEmpty else { return 0 }

        try repository.deleteEvents(withIDs: Array(staleEventIDs))
        try repository.deleteAcknowledgements(withEventIDs: Array(staleEventIDs))

        events.removeAll { staleEventIDs.contains($0.id) }
        acknowledgements.removeAll { staleEventIDs.contains($0.eventID) }
        for runID in staleRunIDs {
            runs.removeValue(forKey: runID)
        }
        recomputeItems(now: now)
        return staleEventIDs.count
    }

    /// Runs eligible for `prune(now:)`: terminal, with no actionable item
    /// left, and old enough -- by both the run's own `updatedAt` and every
    /// one of its items' resolved/acknowledged time -- that nothing about
    /// them is still within `AttentionPolicy.resolvedRetention` of `now`.
    private func prunableRunIDs(now: Date) -> Set<AgentRunID> {
        var result: Set<AgentRunID> = []
        for run in runs.values {
            guard isTerminalRunState(run.state) else { continue }
            guard let updatedAt = run.updatedAt,
                  now.timeIntervalSince(updatedAt) > policy.resolvedRetention
            else { continue }

            let runItems = items.filter { $0.runID == run.id }
            guard !runItems.contains(where: \.isActionable) else { continue }
            let allItemsOldEnough = runItems.allSatisfy { item in
                guard let anchor = [item.resolvedAt, item.acknowledgedAt]
                    .compactMap({ $0 })
                    .min()
                else { return true }
                return now.timeIntervalSince(anchor) > policy.resolvedRetention
            }
            guard allItemsOldEnough else { continue }

            result.insert(run.id)
        }
        return result
    }

    private func isTerminalRunState(_ state: AgentRunState) -> Bool {
        switch state {
        case .idle, .succeeded, .failed, .disconnected:
            true
        case .unknown, .running, .waitingInput, .waitingApproval:
            false
        }
    }

    /// Starts the hourly pruning sweep. A run's terminal transition
    /// already triggers `prune(now:)` from `append(_:)` itself, but a run
    /// can also age past `AttentionPolicy.resolvedRetention` with no new
    /// event ever arriving for it (or for anything else), so this catches
    /// those on a fixed interval instead of relying on activity. Call
    /// once at startup; `stopPruneTimer()` tears it down at app
    /// termination.
    func startPruneTimer() {
        guard pruneTimer == nil else { return }
        let timer = Timer(
            timeInterval: Self.pruneInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                do {
                    try self.prune()
                } catch {
                    WindowSessionCoordinator.reportPersistenceError(
                        error,
                        operation: "prune attention log"
                    )
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    func stopPruneTimer() {
        pruneTimer?.invalidate()
        pruneTimer = nil
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
