import Foundation
import MyTTYCore

/// A pane whose polled foreground process is Codex.
struct CodexAgentPane: Equatable {
    let surfaceID: TerminalSurfaceID
    let processID: pid_t
    let workingDirectory: URL?
}

/// Decides which pane a Codex hook event belongs to. Codex runs sessions in
/// a shared background daemon, so a hook's `MYTTY_*` environment names the
/// pane that happened to start the daemon, not the pane of the session
/// reporting. The pane is derived from the session instead (see
/// `CodexSessionRouter`).
///
/// One instance serves the whole app: panes are gathered from every window,
/// and a binding has to survive a pane being the only thing a later event
/// can be matched on.
@MainActor
final class CodexSessionRoutingCoordinator {
    private var router = CodexSessionRouter()
    private var launchSessionIDs: [pid_t: String?] = [:]

    private let panes: () -> [CodexAgentPane]
    private let processBoundSessionID: (pid_t) -> String?
    private let arguments: (pid_t) -> [String]
    private let metadata: (String) -> CodexSessionMetadata?

    init(
        panes: @escaping () -> [CodexAgentPane],
        processBoundSessionID: @escaping (pid_t) -> String? = {
            CodexSessionInspector.sessionID(processID: $0)
        },
        arguments: @escaping (pid_t) -> [String] = {
            TerminalAgentProcessDetector.arguments(processID: $0)
        },
        metadata: @escaping (String) -> CodexSessionMetadata? = {
            CodexSessionInspector.metadata(sessionID: $0)
        }
    ) {
        self.panes = panes
        self.processBoundSessionID = processBoundSessionID
        self.arguments = arguments
        self.metadata = metadata
    }

    func surface(for event: AgentEvent) -> TerminalSurfaceID? {
        guard event.provider == .codex,
              let sessionID = event.sessionID
        else { return nil }
        let livePanes = panes()
        let candidates = livePanes.map { pane in
            CodexPaneCandidate(
                surfaceID: pane.surfaceID,
                processID: pane.processID,
                processBoundSessionID: processBoundSessionID(pane.processID),
                launchSessionID: launchSessionID(of: pane.processID),
                workingDirectory: pane.workingDirectory
            )
        }
        launchSessionIDs = launchSessionIDs.filter { entry in
            livePanes.contains { $0.processID == entry.key }
        }
        return router.resolve(
            sessionID: sessionID,
            opensSession: Self.sessionOpeningHooks.contains(
                event.hookName ?? ""
            ),
            candidates: candidates,
            metadata: metadata
        )
    }

    /// The hooks a session switched to inside the TUI (`/new`, a resume)
    /// may take its pane over on. `SessionStart` alone is not enough: Codex
    /// writes the rollout the router reads the session's directory from
    /// only once the first prompt is submitted, so a fresh session's
    /// `SessionStart` is never routable and `UserPromptSubmit` is the
    /// first event that is.
    private static let sessionOpeningHooks: Set<String> = [
        "SessionStart", "UserPromptSubmit",
    ]

    /// argv never changes for a process, so it is read once per process id.
    private func launchSessionID(of processID: pid_t) -> String? {
        if let cached = launchSessionIDs[processID] { return cached }
        let value = CodexSessionInspector.resumedSessionID(
            arguments: arguments(processID)
        )
        launchSessionIDs[processID] = .some(value)
        return value
    }
}
