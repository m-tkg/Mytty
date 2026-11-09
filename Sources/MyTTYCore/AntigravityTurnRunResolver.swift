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
    /// Run ID of the `turn`th run (0 is the adapter's own ID) of a
    /// conversation.
    public static func runID(conversationID: String, turn: Int) -> AgentRunID {
        AgentHookEventAdapter.hookAlignedRunID(
            provider: .antigravity,
            runKey: turn == 0
                ? conversationID
                : "\(conversationID)\u{0}turn\u{0}\(turn)"
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
              event.runID == runID(conversationID: conversationID, turn: 0)
        else { return event }

        let byID = Dictionary(
            existingRuns.filter { $0.surfaceID == event.surfaceID }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var turn = 0
        while byID[runID(conversationID: conversationID, turn: turn + 1)] != nil {
            turn += 1
        }
        if event.kind == .running,
           let latest = byID[runID(conversationID: conversationID, turn: turn)],
           latest.state.isTerminalForTurn {
            turn += 1
        }
        guard turn > 0 else { return event }
        return AgentEvent(
            schemaVersion: event.schemaVersion,
            id: event.id,
            runID: runID(conversationID: conversationID, turn: turn),
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
