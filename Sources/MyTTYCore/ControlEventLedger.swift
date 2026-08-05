import Foundation

/// One recorded `AgentEvent`, reduced to the fields `mytty-ctl events`
/// answers travel with — see `ControlEventLedger` and
/// `ControlRequest.events`/`ControlResponse.events` in `ControlProtocol.swift`.
public struct ControlAgentEventRecord: Codable, Equatable, Sendable {
    /// This ledger's monotonically increasing cursor value, starting at 1.
    /// A caller stores the highest `sequence` it has seen and passes it
    /// back as `--after` on the next call.
    public let sequence: UInt64
    /// `TerminalSurfaceID` UUID string, the same form `ControlPaneInfo
    /// .paneID` uses.
    public let paneID: String
    /// `AgentProvider.rawValue`.
    public let provider: String
    /// `AgentRunID` UUID string.
    public let runID: String
    /// `AgentEventKind.rawValue`.
    public let kind: String
    public let occurredAt: Date
    public let toolName: String?
    /// True when the event was synthesized by mytty itself (native run
    /// estimation, Cursor's approval-pending estimate) rather than
    /// delivered by the provider's own hooks — see
    /// `AgentHookEventAdapter.isMyttySynthesizedHookName`.
    public let synthesized: Bool

    public init(
        sequence: UInt64,
        paneID: String,
        provider: String,
        runID: String,
        kind: String,
        occurredAt: Date,
        toolName: String?,
        synthesized: Bool
    ) {
        self.sequence = sequence
        self.paneID = paneID
        self.provider = provider
        self.runID = runID
        self.kind = kind
        self.occurredAt = occurredAt
        self.toolName = toolName
        self.synthesized = synthesized
    }
}

/// Bounded in-memory ring of recorded agent-event summaries backing
/// `mytty-ctl events`, the long-poll fan-in an orchestrating agent uses
/// instead of running one `wait`/`agent wait` per worker pane. Every
/// `append` assigns the next sequence number (a monotonically increasing
/// cursor starting at 1); a caller polls `records(after:)` with the
/// highest cursor it has seen to fetch only what's new. Not persisted —
/// like `ClosedPaneHistory`, an app restart resets it, and sequence
/// numbers start over at 1.
///
/// Pure and unlocked by design: `@MainActor` is the only synchronization,
/// the same choice `ClosedPaneHistory` makes, since every caller (event
/// delivery, `ControlServer`'s poll loop) already runs on the main actor.
@MainActor
public final class ControlEventLedger {
    public static let defaultCapacity = 1000

    private let capacity: Int
    private var records: [ControlAgentEventRecord] = []
    private var nextSequence: UInt64 = 1

    /// The most recently assigned sequence number, or 0 before the first
    /// `append`. Unlike `records`, this is never rolled back by eviction:
    /// a cursor established at the current tip (including via `--after 0`)
    /// stays meaningful even once every record it could point past has
    /// been evicted — it just means `records(after:)` returns nothing
    /// until a genuinely new event lands.
    public private(set) var latestSequence: UInt64 = 0

    public init(capacity: Int = ControlEventLedger.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Records `event` under the next sequence number, evicting the
    /// oldest retained record once `capacity` is exceeded.
    @discardableResult
    public func append(_ event: AgentEvent) -> ControlAgentEventRecord {
        let record = ControlAgentEventRecord(
            sequence: nextSequence,
            paneID: event.surfaceID.rawValue.uuidString,
            provider: event.provider.rawValue,
            runID: event.runID.rawValue.uuidString,
            kind: event.kind.rawValue,
            occurredAt: event.occurredAt,
            toolName: event.toolName,
            synthesized: AgentHookEventAdapter.isMyttySynthesizedHookName(
                event.hookName
            )
        )
        records.append(record)
        nextSequence += 1
        latestSequence = record.sequence
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
        return record
    }

    /// Records newer than `sequence`, oldest first, capped at `limit`.
    /// `sequence` older than the oldest retained record is not an error —
    /// it just means some history in between was evicted, so this simply
    /// returns whatever is still retained. The cursor contract is
    /// at-most-once delivery of retained history, not guaranteed replay: a
    /// caller that stays quiet longer than it takes `capacity` events to
    /// accumulate across every pane silently skips the events in between.
    public func records(
        after sequence: UInt64,
        limit: Int = 200
    ) -> [ControlAgentEventRecord] {
        Array(records.filter { $0.sequence > sequence }.prefix(limit))
    }
}
