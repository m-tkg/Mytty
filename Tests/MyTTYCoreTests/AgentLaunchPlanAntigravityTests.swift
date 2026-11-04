import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent launch plan: Antigravity")
struct AgentLaunchPlanAntigravityTests {
    private func input(
        access: AgentAccessPolicy,
        model: String? = nil,
        effort: AgentReasoningEffort? = nil,
        inherited: [String]? = nil,
        task: String = "do the thing"
    ) -> String {
        AgentLaunchPlan.initialInput(
            provider: .antigravity,
            access: access,
            model: model,
            reasoningEffort: effort,
            inheritedModeArguments: inherited,
            task: task
        )
    }

    private func command(_ input: String) -> String {
        String(input.dropFirst(AgentLaunchPlan.historySuppressionPrefix.count))
    }

    @Test("review launches in plan mode with the read-only allow rules")
    func reviewUsesPlanMode() {
        let line = command(input(access: .review))
        #expect(line.hasPrefix("command agy --mode plan --settings "))
        #expect(line.contains("command(gh pr view)"))
        #expect(line.contains("command(gh pr diff)"))
        #expect(line.contains("command(gh api)"))
        #expect(line.contains("command(git diff)"))
        #expect(line.contains("command(mytty-ctl status)"))
        // Review must not be able to push or build.
        #expect(!line.contains("command(git push)"))
        #expect(!line.contains("command(swift)"))
    }

    @Test("workspace-write launches in accept-edits mode with the broader allow rules")
    func workspaceWriteUsesAcceptEdits() {
        let line = command(input(access: .workspaceWrite))
        #expect(line.hasPrefix("command agy --mode accept-edits --settings "))
        #expect(line.contains("command(git)"))
        #expect(line.contains("command(gh)"))
        #expect(line.contains("command(swift)"))
        #expect(line.contains("command(make)"))
    }

    @Test("settings pre-trust the pane's working directory and are session-only JSON")
    func settingsTrustWorkingDirectory() {
        let line = command(input(access: .review))
        #expect(line.contains(#"{"trustedWorkspaces":["%s"],"permissions":{"allow":["#))
        #expect(line.contains(#""$PWD")"#))
    }

    @Test("the task is passed as the quoted initial interactive prompt")
    func taskUsesPromptInteractive() {
        let line = command(input(access: .review, task: "it's a task"))
        #expect(line.contains(" -i 'it'\\''s a task"))
        #expect(line.hasSuffix("'\n"))
        #expect(line.contains("Mytty worker contract:"))
    }

    @Test("a task starting with a dash stays a quoted value of -i")
    func dashTask() {
        let line = command(input(access: .review, task: "--help"))
        #expect(line.contains(" -i '--help"))
    }

    @Test("model and reasoning effort lead the launch options")
    func modelAndEffort() {
        let line = command(input(
            access: .review,
            model: "gemini-4-argon-medium",
            effort: .high
        ))
        #expect(line.hasPrefix(
            "command agy --model 'gemini-4-argon-medium' --effort high --mode plan "
        ))
    }

    @Test("a nil model and effort add no flags")
    func noModelNoEffort() {
        let line = command(input(access: .workspaceWrite))
        #expect(!line.contains("--model"))
        #expect(!line.contains("--effort"))
    }

    @Test("inherit with no resolved flags falls back to workspace-write")
    func inheritFallback() {
        #expect(command(input(access: .inherit))
            == command(input(access: .workspaceWrite)))
    }

    @Test("inherited mode flags replace the mode flag but keep trust and allow settings")
    func inheritedFlags() {
        let line = command(input(
            access: .inherit,
            inherited: ["--mode", "plan", "--sandbox"]
        ))
        #expect(line.hasPrefix("command agy '--mode' 'plan' '--sandbox' --settings "))
        #expect(!line.contains("accept-edits"))
        #expect(line.contains("trustedWorkspaces"))
    }

    @Test("antigravity accepts low through max reasoning effort")
    func supportedEfforts() {
        #expect(
            AgentReasoningEffort.supportedValues(for: .antigravity)
                == [.low, .medium, .high, .xhigh, .max]
        )
        #expect(!AgentReasoningEffort.minimal.isSupported(by: .antigravity))
    }

    @Test("antigravity reports as the antigravity hook provider")
    func agentProviderMapping() {
        #expect(AgentWorkerProvider.antigravity.agentProvider == .antigravity)
        #expect(AgentWorkerProvider(rawValue: "antigravity") == .antigravity)
    }

    @Test("inherited argv scanning recognises agy's mode flags")
    func modeInheritanceFlags() {
        let args = AgentModeInheritance.inheritedModeArguments(
            provider: .antigravity,
            leadArguments: [
                "agy", "--model", "x", "--mode", "plan", "--sandbox",
                "--dangerously-skip-permissions", "-i", "hello",
            ]
        )
        #expect(args == ["--mode", "plan", "--sandbox", "--dangerously-skip-permissions"])
    }
}
