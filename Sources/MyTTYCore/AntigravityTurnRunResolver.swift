import Foundation

/// Gives each Antigravity turn its own run.
///
/// agy's hook payloads carry only the `conversationId`, which stays the same
/// for every prompt in a conversation, so `AgentHookEventAdapter` maps all of
/// them onto one run. The reducer never leaves a terminal state on `running`,
/// so once the first turn's `Stop` landed, every later turn's events were
/// absorbed by that finished run: `agent send` could never bind a new run
/// (the job went `launch-failed`) and the pane looked idle while agy worked.
///
/// The first turn keeps the adapter's run ID. When a `running` event arrives
/// and the conversation's newest run is already terminal, this opens the next
/// turn's run; every other event follows the newest run.
public enum AntigravityTurnRunResolver {
    /// The adapter's own run ID for a conversation (the first turn's run).
    public static func baseRunID(conversationID: String) -> AgentRunID {
        AgentHookEventAdapter.hookAlignedRunID(
            provider: .antigravity,
            runKey: conversationID
        )
    }

    /// Run ID for a later turn, derived from the event that opens it. It
    /// is deterministic (a redelivery of the opener maps to the same run)
    /// and does not depend on how many earlier runs still exist, so
    /// `AttentionCenter.prune` dropping old turns cannot make it collide
    /// with or skip over another turn.
    static func turnRunID(
        conversationID: String,
        opening event: AgentEvent
    ) -> AgentRunID {
        let millis = Int64((event.occurredAt.timeIntervalSince1970 * 1000).rounded())
        return AgentHookEventAdapter.hookAlignedRunID(
            provider: .antigravity,
            runKey: "\(conversationID)\u{0}turn\u{0}\(event.id.rawValue.uuidString)\u{0}\(millis)"
        )
    }

    /// `existingRuns` are the runs already known for the event's pane.
    /// Events that are not Antigravity hook events, or that have no session
    /// ID, are returned unchanged.
    public static func resolve(
        _ event: AgentEvent,
        existingRuns: [AgentRun]
    ) -> AgentEvent {
        guard event.provider == .antigravity,
              !AgentHookEventAdapter.isMyttySynthesizedHookName(event.hookName),
              let conversationID = event.sessionID,
              event.runID == baseRunID(conversationID: conversationID)
        else { return event }

        // Every turn's run carries the conversation ID as its session, so
        // the newest one is found by time rather than by counting turns
        // (earlier turns may already have been pruned).
        let latest = existingRuns
            .filter {
                $0.surfaceID == event.surfaceID
                    && $0.provider == .antigravity
                    && $0.sessionID == conversationID
            }
            .max { lhs, rhs in
                (lhs.startedAt ?? lhs.updatedAt ?? .distantPast)
                    < (rhs.startedAt ?? rhs.updatedAt ?? .distantPast)
            }
        guard let latest else { return event }

        let targetID: AgentRunID
        if event.kind == .running, latest.state.isTerminalForTurn {
            targetID = turnRunID(conversationID: conversationID, opening: event)
        } else {
            targetID = latest.id
        }
        guard targetID != event.runID else { return event }

        // Redirected events get an identity of their own: the adapter
        // derives `id` from the payload alone, so an identical payload in
        // a later turn (same `executionNum`, same prompt) would otherwise
        // be dropped as a duplicate of the earlier turn's event. Deriving
        // it from (original id, run) keeps redelivery idempotent.
        return AgentEvent(
            schemaVersion: event.schemaVersion,
            id: AgentEventID(
                rawValue: StableAgentUUID.make(
                    from: "event\u{0}antigravity-turn\u{0}\(event.id.rawValue.uuidString)\u{0}\(targetID.rawValue.uuidString)"
                )
            ),
            runID: targetID,
            sessionID: event.sessionID,
            surfaceID: event.surfaceID,
            provider: event.provider,
            kind: event.kind,
            occurredAt: event.occurredAt,
            message: event.message,
            hookName: event.hookName,
            toolUseID: event.toolUseID,
            toolName: event.toolName
        )
    }
}

private extension AgentRunState {
    var isTerminalForTurn: Bool {
        self == .succeeded || self == .failed || self == .disconnected
    }
}
