import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// The pane bar's content is assembled by a pure function so the rules —
/// which field wins the trailing slot, what stays in the tooltip — can be
/// checked without a window. No test may depend on a real repository on
/// disk: `GitHubRepositoryStatus` values are built directly.
@Suite("Pane status bar presentation")
struct PaneStatusBarPresentationTests {
    private let labels = PaneStatusBarLabels(
        openOnGitHub: "Open on GitHub",
        branch: "Branch",
        sessionID: "Session ID"
    )
    private let repository = GitHubRepositoryStatus(
        pageURL: URL(string: "https://github.com/m-tkg/Mytty")!,
        branchName: "main"
    )

    private func content(
        agentName: String? = nil,
        agentSessionID: String? = nil,
        agentModelName: String? = nil,
        contextTooltip: String? = nil,
        processName: String? = nil,
        repository: GitHubRepositoryStatus? = nil
    ) -> PaneStatusBarContent {
        PaneStatusBarPresentation.content(
            agentName: agentName,
            agentSessionID: agentSessionID,
            agentModelName: agentModelName,
            contextTooltip: contextTooltip,
            processName: processName,
            repository: repository,
            labels: labels
        )
    }

    @Test("shortens an agent session ID to eight characters")
    func shortensSessionID() {
        let result = content(
            agentName: "Claude Code",
            agentSessionID: "0199aa11-2b3c-4d5e-8f90-abcdef012345",
            processName: "claude"
        )

        #expect(result.agentName == "Claude Code")
        #expect(result.trailingText == "0199aa11")
    }

    @Test("keeps a session ID that is already short")
    func keepsShortSessionID() {
        let result = content(agentName: "Codex", agentSessionID: "abc123")

        #expect(result.trailingText == "abc123")
    }

    @Test("falls back to the foreground process name without an agent")
    func processNameWithoutAgent() {
        let result = content(processName: "zsh")

        #expect(result.agentName == nil)
        #expect(result.trailingText == "zsh")
        #expect(result.tooltip == nil)
    }

    @Test("does not repeat the executable behind a running agent")
    func agentWithoutSessionIDShowsNoProcessName() {
        let result = content(agentName: "Claude Code", processName: "claude")

        #expect(result.trailingText == nil)
    }

    @Test("omits the repository mark outside a git working tree")
    func noRepository() {
        let result = content(processName: "zsh")

        #expect(result.repositoryURL == nil)
        #expect(result.branchName == nil)
    }

    @Test("shows the repository page and branch inside a working tree")
    func withRepository() {
        let result = content(processName: "zsh", repository: repository)

        #expect(result.repositoryURL == repository.pageURL)
        #expect(result.branchName == "main")
    }

    @Test("puts the model, remaining context and full session ID in the tooltip only")
    func tooltipCarriesTheDetails() {
        let result = content(
            agentName: "Claude Code",
            agentSessionID: "0199aa11-2b3c-4d5e-8f90-abcdef012345",
            agentModelName: "Opus 5",
            contextTooltip: "Context 64% left"
        )

        #expect(result.tooltip == """
        Opus 5 · Context 64% left · \
        Session ID 0199aa11-2b3c-4d5e-8f90-abcdef012345
        """)
        // None of that is repeated in the bar itself.
        #expect(result.agentName == "Claude Code")
        #expect(result.trailingText == "0199aa11")
    }

    @Test("omits the tooltip when nothing is known beyond the agent name")
    func noTooltipWithoutDetails() {
        let result = content(agentName: "Codex")

        #expect(result.tooltip == nil)
    }

    @Test("reports empty content for a pane with nothing to show")
    func emptyContent() {
        #expect(content().isEmpty)
        #expect(!content(processName: "zsh").isEmpty)
        #expect(!content(repository: repository).isEmpty)
    }
}
