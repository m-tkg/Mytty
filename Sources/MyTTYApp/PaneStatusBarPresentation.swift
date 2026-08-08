import Foundation
import MyTTYCore

/// What one pane's own status bar shows. Deliberately a much smaller model
/// than `TerminalStatusBarContent`: the window status bar describes the
/// focused pane in full (bookmarks, schedules, quota meters, sleep), while a
/// pane bar only has to answer "which repository, which agent, which
/// program" at a glance for every pane at once.
struct PaneStatusBarContent: Equatable {
    /// The GitHub page for the pane's repository. The mark is shown only
    /// when this is set, matching the window status bar.
    var repositoryURL: URL?
    var branchName: String?
    var agentName: String?
    /// The agent's session ID, shortened, or the foreground program's name
    /// when no agent is running in the pane.
    var trailingText: String?
    /// Model name, remaining context and the full session ID — details that
    /// would crowd a bar repeated once per pane, so they live in the
    /// tooltip.
    var tooltip: String?

    init(
        repositoryURL: URL? = nil,
        branchName: String? = nil,
        agentName: String? = nil,
        trailingText: String? = nil,
        tooltip: String? = nil
    ) {
        self.repositoryURL = repositoryURL
        self.branchName = branchName
        self.agentName = agentName
        self.trailingText = trailingText
        self.tooltip = tooltip
    }

    /// Nothing is known about the pane yet. The bar stays on screen anyway
    /// (hiding it would resize the terminal for one poll tick); this is here
    /// for callers that want to describe a pane, not to gate the bar.
    var isEmpty: Bool {
        repositoryURL == nil
            && branchName == nil
            && agentName == nil
            && trailingText == nil
    }
}

/// Pre-localized strings handed to the AppKit pane bar, so the view itself
/// stays free of `MyTTYLocalizer` — the same arrangement `RemotePaneLabels`
/// uses for the remote pane header.
struct PaneStatusBarLabels: Equatable {
    var openOnGitHub: String
    var branch: String
    var sessionID: String

    init(openOnGitHub: String, branch: String, sessionID: String) {
        self.openOnGitHub = openOnGitHub
        self.branch = branch
        self.sessionID = sessionID
    }
}

enum PaneStatusBarPresentation {
    /// How much of a session ID the bar shows. Enough to tell two panes'
    /// sessions apart at a glance; the full value is in the tooltip.
    static let sessionIDPrefixLength = 8

    static func content(
        agentName: String?,
        agentSessionID: String?,
        agentModelName: String?,
        contextTooltip: String?,
        processName: String?,
        repository: GitHubRepositoryStatus?,
        labels: PaneStatusBarLabels
    ) -> PaneStatusBarContent {
        // With an agent running, its name is already the third field, so
        // repeating the executable behind it ("Claude Code · claude") would
        // say nothing new: show which session it is instead.
        let trailingText = agentName == nil
            ? processName
            : agentSessionID.map(shortenedSessionID)
        let tooltip = [
            agentModelName,
            contextTooltip,
            agentSessionID.map { "\(labels.sessionID) \($0)" },
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
        return PaneStatusBarContent(
            repositoryURL: repository?.pageURL,
            branchName: repository?.branchName,
            agentName: agentName,
            trailingText: trailingText,
            tooltip: tooltip.isEmpty ? nil : tooltip
        )
    }

    static func shortenedSessionID(_ sessionID: String) -> String {
        String(sessionID.prefix(sessionIDPrefixLength))
    }
}
