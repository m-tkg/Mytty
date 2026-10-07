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

    /// Resolution order, each step failing closed:
    /// 1. drop claims whose pane is gone or whose process was replaced;
    /// 2. the pane whose own process holds the session's rollout open;
    /// 3. a pane this session already claimed;
    /// 4. the pane launched with `codex resume <session>`;
    /// 5. the one unbound pane in the session's working directory;
    /// 6. only for an event that opens a session or a turn
    ///    (`opensSession`), the one pane in that directory still held by a
    ///    binding that cannot be authoritative (`/new` or a resume inside
    ///    the TUI), which the new session takes over.
    public mutating func resolve(
        sessionID: String,
        opensSession: Bool,
        candidates: [CodexPaneCandidate],
        metadata: (String) -> CodexSessionMetadata?
    ) -> TerminalSurfaceID? {
        var panes: [TerminalSurfaceID: CodexPaneCandidate] = [:]
        for candidate in candidates where panes[candidate.surfaceID] == nil {
            panes[candidate.surfaceID] = candidate
        }
        claims = claims.filter {
            panes[$0.value.surfaceID]?.processID == $0.value.processID
        }

        let processBound = candidates.filter {
            $0.processBoundSessionID == sessionID
        }
        guard processBound.count <= 1 else { return nil }
        if let pane = processBound.first { return pane.surfaceID }

        if let claim = claims[sessionID],
           let pane = panes[claim.surfaceID] {
            if pane.processBoundSessionID == nil {
                return pane.surfaceID
            }
            claims[sessionID] = nil
        }

        let launched = candidates.filter {
            $0.launchSessionID == sessionID
                && $0.processBoundSessionID == nil
                && claimedSession(of: $0.surfaceID) == nil
        }
        guard launched.count <= 1 else { return nil }
        if let pane = launched.first { return bind(sessionID, to: pane) }

        guard let metadata = metadata(sessionID),
              metadata.sessionID == sessionID
        else { return nil }
        let directory = Self.comparableDirectory(metadata.workingDirectory)
        let inDirectory = candidates.filter {
            $0.workingDirectory.map(Self.comparableDirectory) == directory
                && $0.processBoundSessionID == nil
        }

        let eligible = inDirectory.filter {
            $0.launchSessionID == nil
                && claimedSession(of: $0.surfaceID) == nil
        }
        guard eligible.count <= 1 else { return nil }
        if let pane = eligible.first { return bind(sessionID, to: pane) }

        guard opensSession else { return nil }
        // Anything in `inDirectory` is held by a claim (necessarily another
        // session's: this session's was handled above) or a stale resume
        // argument, since the eligible set is empty.
        guard inDirectory.count == 1, let pane = inDirectory.first else {
            return nil
        }
        return bind(sessionID, to: pane)
    }

    private func claimedSession(of surfaceID: TerminalSurfaceID) -> String? {
        claims.first { $0.value.surfaceID == surfaceID }?.key
    }

    private mutating func bind(
        _ sessionID: String,
        to pane: CodexPaneCandidate
    ) -> TerminalSurfaceID {
        claims = claims.filter {
            $0.key != sessionID && $0.value.surfaceID != pane.surfaceID
        }
        claims[sessionID] = Claim(
            surfaceID: pane.surfaceID,
            processID: pane.processID
        )
        return pane.surfaceID
    }

    private static func comparableDirectory(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
