import Foundation
import MyTTYCore

@MainActor
final class AttentionCenter: ObservableObject {
    @Published private(set) var items: [AttentionItem] = []
    @Published private(set) var runs: [AgentRunID: AgentRun] = [:]

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
            try reload()
        }
        return inserted
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
        let matchingItems = items.filter {
            $0.surfaceID == surfaceID && $0.isActionable
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
