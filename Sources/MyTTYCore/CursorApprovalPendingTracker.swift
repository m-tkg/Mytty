import Foundation

/// Estimates the one Cursor signal its hooks never send: a shell command
/// stuck on a permission prompt. Cursor has no dedicated approval-request
/// hook, but `beforeShellExecution` / `afterShellExecution` bracket every
/// command; if no forward-progress hook for the same run follows
/// `beforeShellExecution` within `threshold`, the command is presumed
/// waiting on the user.
///
/// Pure state machine: callers feed it observed events plus the current
/// time and act on the returned deadline. It owns no timer itself — see
/// `CursorApprovalCoordinator` in `MyTTYApp`, which pairs this with an
/// actual `Timer` (the same split `ClamshellHelperCore` uses between
/// logic and effects).
public final class CursorApprovalPendingTracker {
    public struct FiredApproval: Equatable, Sendable {
        public let runID: AgentRunID
        public let command: String
        public let sessionID: String?
        public let surfaceID: TerminalSurfaceID
    }

    private struct Key: Hashable {
        let runID: AgentRunID
        let command: String
    }

    private struct Registration {
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

        switch event.hookName {
        case "beforeShellExecution":
            if let command = event.message, !command.isEmpty {
                let key = Key(runID: event.runID, command: command)
                if pending[key] == nil {
                    pending[key] = Registration(
                        sessionID: event.sessionID,
                        surfaceID: event.surfaceID,
                        deadline: now.addingTimeInterval(threshold)
                    )
                }
            }
        case "afterShellExecution":
            if let command = event.message {
                pending.removeValue(
                    forKey: Key(runID: event.runID, command: command)
                )
            } else {
                removeAll(for: event.runID)
            }
        case "postToolUse", "postToolUseFailure", "stop":
            removeAll(for: event.runID)
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
                    command: key.command,
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
