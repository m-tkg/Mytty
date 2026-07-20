import AppKit
import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Terminal status bar view")
struct TerminalStatusBarViewTests {
    @Test("builds status content from the active pane")
    func statusBarContent() {
        let usage = AgentUsageStatusContent(
            costDescription: "$0.42",
            limits: [
                AgentUsageMeterContent(
                    title: "5h",
                    remainingPercent: 73
                ),
            ]
        )
        let content = TerminalStatusBarContent(
            resource: "~/git/mytty",
            canRevealInFinder: true,
            repositoryURL: URL(string: "https://github.com/m-tkg/Mytty"),
            branchName: "main",
            agentName: "Codex",
            agentSessionID: "codex-session-01",
            agentModelName: "gpt-5.4-mini",
            agentState: "Running",
            agentUsage: usage,
            agentContext: AgentUsageMeterContent(
                title: "Context",
                remainingPercent: 64
            ),
            sleepStatus: AgentSleepStatus(
                mode: .preventWhileProcessing,
                isActive: true
            ),
            canScheduleInput: true,
            scheduledInputCount: 2
        )

        #expect(content.resource == "~/git/mytty")
        #expect(content.canRevealInFinder)
        #expect(
            content.repositoryURL?.absoluteString
                == "https://github.com/m-tkg/Mytty"
        )
        #expect(content.branchName == "main")
        #expect(content.agentSessionID == "codex-session-01")
        #expect(content.copyableAgentSessionID == "codex-session-01")
        #expect(
            content.agentDescription
                == "Codex · gpt-5.4-mini · Running · $0.42"
        )
        #expect(
            content.visibleAgentUsageLimits.map(\.title)
                == ["Context", "5h"]
        )
        #expect(content.canScheduleInput)
        #expect(content.scheduledInputCount == 2)
        #expect(
            content.sleepStatus
                == AgentSleepStatus(
                    mode: .preventWhileProcessing,
                    isActive: true
                )
        )

        let inactive = TerminalStatusBarContent(
            agentSessionID: "hidden-session",
            agentUsage: usage
        )
        #expect(inactive.agentDescription == nil)
        #expect(inactive.copyableAgentSessionID == nil)
        #expect(inactive.visibleAgentUsageLimits.isEmpty)
    }

    @Test("orders agent controls before sleep and scheduled input")
    func statusBarTrailingItemOrder() {
        #expect(
            TerminalStatusBarLayout.trailingItems
                == [.agent, .sleepPrevention, .scheduledInput]
        )
        #expect(TerminalStatusBarLayout.trailingUsesIntrinsicWidth)
    }

    @Test("copies the session ID from the agent status menu")
    @MainActor
    func statusBarSessionIDCopyAction() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("mytty-session-id-test-\(UUID().uuidString)")
        )
        defer { pasteboard.clearContents() }
        let model = TerminalStatusBarModel()
        model.content = TerminalStatusBarContent(
            agentName: "Codex",
            agentSessionID: "codex-session-01"
        )
        let view = TerminalStatusBarView(
            model: model,
            revealInFinderTitle: "Reveal in Finder",
            onRevealInFinder: {}
        )

        view.copySessionID(to: pasteboard)

        #expect(
            pasteboard.string(forType: .string) == "codex-session-01"
        )
    }

    @Test("routes the sleep status menu to the mode selection callback")
    @MainActor
    func statusBarSleepModeSelectionAction() {
        let model = TerminalStatusBarModel()
        var selectedModes: [AgentSleepPreventionMode] = []
        let view = TerminalStatusBarView(
            model: model,
            revealInFinderTitle: "Reveal in Finder",
            onRevealInFinder: {},
            onSelectSleepPreventionMode: { selectedModes.append($0) }
        )

        view.onSelectSleepPreventionMode(.preventWhileLaunched)

        #expect(selectedModes == [.preventWhileLaunched])
    }

    @Test("routes the status resource button to Finder")
    @MainActor
    func statusBarRevealAction() {
        let model = TerminalStatusBarModel()
        model.content = TerminalStatusBarContent(
            resource: "~/git/mytty",
            canRevealInFinder: true
        )
        var revealCount = 0
        let view = TerminalStatusBarView(
            model: model,
            revealInFinderTitle: "Reveal in Finder",
            onRevealInFinder: { revealCount += 1 }
        )

        view.revealResourceInFinder()

        #expect(revealCount == 1)
    }

    @Test("routes the repository button to GitHub")
    @MainActor
    func statusBarRepositoryAction() {
        let model = TerminalStatusBarModel()
        model.content = TerminalStatusBarContent(
            resource: "~/git/mytty",
            repositoryURL: URL(string: "https://github.com/m-tkg/Mytty"),
            branchName: "main"
        )
        var openCount = 0
        let view = TerminalStatusBarView(
            model: model,
            revealInFinderTitle: "Reveal in Finder",
            onRevealInFinder: {},
            openRepositoryTitle: "Open on GitHub",
            onOpenRepository: { openCount += 1 }
        )

        view.openRepository()

        #expect(openCount == 1)
    }
}
