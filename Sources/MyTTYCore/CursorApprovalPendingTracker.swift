import Foundation

/// Estimates the one Cursor signal its hooks never send: a tool call
/// stuck on a permission prompt. Cursor has no dedicated approval-request
/// hook, but `preToolUse` brackets every tool call (shell or otherwise —
/// file edits and deletes prompt for approval too, not just shell
/// commands); if no matching `postToolUse` / `postToolUseFailure` for the
/// same `tool_use_id` follows within `threshold`, the call is presumed
/// waiting on the user.
///
/// Tool calls can run concurrently — Cursor has been observed firing
/// `preToolUse` for two different tools back to back before either one's
/// `postToolUse` arrives — so pending registrations are keyed by
/// `(runID, toolUseID)`, never by run alone, or a still-pending tool
/// would be forgotten as soon as any other tool in the same run resolves.
///
/// Pure state machine: callers feed it observed events plus the current
/// time and act on the returned deadline. It owns no timer itself — see
/// `CursorApprovalCoordinator` in `MyTTYApp`, which pairs this with an
/// actual `Timer` (the same split `ClamshellHelperCore` uses between
/// logic and effects).
public final class CursorApprovalPendingTracker {
    public struct FiredApproval: Equatable, Sendable {
        public let runID: AgentRunID
        public let toolUseID: String
        public let toolName: String
        public let sessionID: String?
        public let surfaceID: TerminalSurfaceID
    }

    private struct Key: Hashable {
        let runID: AgentRunID
        let toolUseID: String
    }

    private struct Registration {
        let toolName: String
        let sessionID: String?
        let surfaceID: TerminalSurfaceID
        let deadline: Date
    }

    private let threshold: TimeInterval
    private var pending: [Key: Registration] = [:]

    public init(threshold: TimeInterval = 10) {
        self.threshold = threshold
    }

    /// The soonest deadline still pending, or `nil` if nothing is
    /// waiting. The caller (re)arms its single timer for this value after
    /// every call to `handle` or `fireDue`.
    public var nextDeadline: Date? {
        pending.values.map(\.deadline).min()
    }

    /// Feed every `AgentEvent` observed for a Cursor surface here,
    /// including synthetic ones this tracker itself produced (they carry
    /// `AgentHookEventAdapter.syntheticPendingApprovalHookName`, which
    /// this switch ignores, so they can't re-register).
    @discardableResult
    public func handle(_ event: AgentEvent, now: Date) -> Date? {
        guard event.provider == .cursor else { return nextDeadline }

        // A run-ending kind clears every tool call still pending for that
        // run, regardless of which hook produced it.
        if event.kind == .succeeded
            || event.kind == .failed
            || event.kind == .disconnected {
            removeAll(for: event.runID)
            return nextDeadline
        }

        switch event.hookName {
        case "preToolUse":
            if let toolUseID = event.toolUseID, !toolUseID.isEmpty {
                let key = Key(runID: event.runID, toolUseID: toolUseID)
                if pending[key] == nil {
                    pending[key] = Registration(
                        toolName: event.message ?? "",
                        sessionID: event.sessionID,
                        surfaceID: event.surfaceID,
                        deadline: now.addingTimeInterval(threshold)
                    )
                }
            }
        case "postToolUse", "postToolUseFailure":
            if let toolUseID = event.toolUseID {
                pending.removeValue(
                    forKey: Key(runID: event.runID, toolUseID: toolUseID)
                )
            }
        default:
            break
        }

        return nextDeadline
    }

    /// Removes and returns entries whose deadline has passed. The caller
    /// synthesizes an `approval-requested` event for each and rearms its
    /// timer using `nextDeadline`.
    public func fireDue(now: Date) -> [FiredApproval] {
        let dueKeys = pending.filter { $0.value.deadline <= now }.map(\.key)
        var fired: [FiredApproval] = []
        for key in dueKeys {
            guard let registration = pending.removeValue(forKey: key)
            else { continue }
            fired.append(
                FiredApproval(
                    runID: key.runID,
                    toolUseID: key.toolUseID,
                    toolName: registration.toolName,
                    sessionID: registration.sessionID,
                    surfaceID: registration.surfaceID
                )
            )
        }
        return fired
    }

    private func removeAll(for runID: AgentRunID) {
        for key in pending.keys where key.runID == runID {
            pending.removeValue(forKey: key)
        }
    }
}
