import Darwin
import Foundation

/// One live Codex pane the router may bind a session to.
public struct CodexPaneCandidate: Equatable, Sendable {
    public let surfaceID: TerminalSurfaceID
    public let processID: pid_t
    /// The session whose rollout the pane's own process holds open. The
    /// only authoritative binding.
    public let processBoundSessionID: String?
    /// The session named by `codex resume <id>` on the pane's argv. Only an
    /// initial binding: `/new` inside the TUI leaves it stale.
    public let launchSessionID: String?
    public let workingDirectory: URL?

    public init(
        surfaceID: TerminalSurfaceID,
        processID: pid_t,
        processBoundSessionID: String? = nil,
        launchSessionID: String? = nil,
        workingDirectory: URL? = nil
    ) {
        self.surfaceID = surfaceID
        self.processID = processID
        self.processBoundSessionID = processBoundSessionID
        self.launchSessionID = launchSessionID
        self.workingDirectory = workingDirectory
    }
}

/// What the router needs to know about a session from its rollout.
public struct CodexSessionMetadata: Equatable, Sendable {
    public let sessionID: String
    public let workingDirectory: URL

    public init(sessionID: String, workingDirectory: URL) {
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
    }
}

/// Maps a Codex session id to the pane it runs in. Codex hooks are spawned
/// by a shared background daemon, so the environment they carry names
/// whichever pane started the daemon, not the pane the session belongs to.
/// The router therefore ignores that and decides from the session itself,
/// failing closed (`nil`) whenever the answer is not unique.
public struct CodexSessionRouter: Sendable {
    private struct Claim: Equatable, Sendable {
        var surfaceID: TerminalSurfaceID
        var processID: pid_t
    }

    private var claims: [String: Claim] = [:]

    public init() {}

    public mutating func resolve(
        sessionID: String,
        isSessionStart: Bool,
        candidates: [CodexPaneCandidate],
        metadata: (String) -> CodexSessionMetadata?
    ) -> TerminalSurfaceID? {
        nil
    }
}
