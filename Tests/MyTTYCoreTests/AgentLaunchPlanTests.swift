import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent launch plan")
struct AgentLaunchPlanTests {
    @Test("maps every provider/access pair to its exact launch command")
    func providerAccessCommandMapping() {
        let cases: [(AgentWorkerProvider, AgentAccessPolicy, String)] = [
            (.codex, .review, "command codex -s read-only -a never -- "),
            (.codex, .workspaceWrite, "command codex -s workspace-write -a never -- "),
            (.claude, .review, "command claude --permission-mode plan -- "),
            (.claude, .workspaceWrite, "command claude --permission-mode acceptEdits -- "),
            (.cursor, .review, "command cursor-agent --mode plan -- "),
            (.cursor, .workspaceWrite, "command cursor-agent --force --sandbox enabled -- "),
        ]

        for (provider, access, expectedPrefix) in cases {
            let input = AgentLaunchPlan.initialInput(
                provider: provider,
                access: access,
                model: nil,
                task: "do the thing"
            )
            #expect(input.hasPrefix(expectedPrefix))
        }
    }

    @Test("appends the worker contract exactly once")
    func workerContractAppendedOnce() {
        let input = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            task: "investigate the bug"
        )
        let occurrences = input.components(
            separatedBy: "Mytty worker contract:"
        ).count - 1
        #expect(occurrences == 1)
        #expect(input.contains("investigate the bug"))
        #expect(input.contains(
            "Do not create hidden/native sub-agents."
        ))
    }

    @Test("ends with exactly one trailing newline")
    func trailingNewline() {
        let input = AgentLaunchPlan.initialInput(
            provider: .claude,
            access: .workspaceWrite,
            model: nil,
            task: "task"
        )
        #expect(input.hasSuffix("\n"))
        #expect(!input.hasSuffix("\n\n"))
    }

    @Test("shell-quotes a task containing spaces")
    func quotesSpaces() {
        let input = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            task: "fix the login bug"
        )
        #expect(input.contains("'fix the login bug"))
    }

    @Test("shell-quotes a task containing single quotes")
    func quotesSingleQuotes() {
        let input = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            task: "don't break it"
        )
        #expect(input.contains("don'\\''t break it"))
    }

    @Test("shell-quotes a task containing embedded newlines")
    func quotesNewlines() {
        let input = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            task: "line one\nline two"
        )
        // The whole quoted argument, contract included, must stay inside a
        // single pair of quotes — an unescaped raw newline anywhere in it
        // would otherwise submit the shell command early.
        let quoteCount = input.filter { $0 == "'" }.count
        #expect(quoteCount >= 2)
        #expect(input.contains("line one\nline two"))
        #expect(!input.hasPrefix("line one"))
    }

    @Test("shell-quotes a task starting with a leading dash")
    func quotesLeadingDash() {
        let input = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            task: "--rm -rf /"
        )
        // A leading dash must stay inside the quoted argument rather than
        // being parsed as a flag of the launch command itself.
        #expect(input.contains("-- '--rm -rf /"))
    }

    @Test("shell-quotes non-ASCII task text without mangling it")
    func quotesNonASCII() {
        let input = AgentLaunchPlan.initialInput(
            provider: .cursor,
            access: .workspaceWrite,
            model: nil,
            task: "日本語のタスク 🎉"
        )
        #expect(input.contains("日本語のタスク 🎉"))
    }

    @Test("inserts each provider's model flag, quoted, ahead of its other launch flags")
    func modelFlagPerProvider() {
        let cases: [(AgentWorkerProvider, AgentAccessPolicy, String)] = [
            (.codex, .review, "command codex -m 'gpt-5.2' -s read-only -a never -- "),
            (.codex, .workspaceWrite, "command codex -m 'gpt-5.2' -s workspace-write -a never -- "),
            (.claude, .review, "command claude --model 'sonnet' --permission-mode plan -- "),
            (.claude, .workspaceWrite, "command claude --model 'sonnet' --permission-mode acceptEdits -- "),
            (.cursor, .review, "command cursor-agent --model 'sonnet' --mode plan -- "),
            (.cursor, .workspaceWrite, "command cursor-agent --model 'sonnet' --force --sandbox enabled -- "),
        ]

        for (provider, access, expectedPrefix) in cases {
            let model = provider == .codex ? "gpt-5.2" : "sonnet"
            let input = AgentLaunchPlan.initialInput(
                provider: provider,
                access: access,
                model: model,
                task: "do the thing"
            )
            #expect(input.hasPrefix(expectedPrefix))
        }
    }

    @Test("shell-quotes a model containing a single quote")
    func quotesModelWithSingleQuote() {
        let input = AgentLaunchPlan.initialInput(
            provider: .claude,
            access: .workspaceWrite,
            model: "weird'model",
            task: "task"
        )
        #expect(input.contains("--model 'weird'\\''model' --permission-mode acceptEdits"))
    }

    @Test("a nil model leaves the launch command byte-for-byte unchanged")
    func nilModelKeepsCommandUnchanged() {
        let cases: [(AgentWorkerProvider, AgentAccessPolicy, String)] = [
            (.codex, .review, "command codex -s read-only -a never -- "),
            (.codex, .workspaceWrite, "command codex -s workspace-write -a never -- "),
            (.claude, .review, "command claude --permission-mode plan -- "),
            (.claude, .workspaceWrite, "command claude --permission-mode acceptEdits -- "),
            (.cursor, .review, "command cursor-agent --mode plan -- "),
            (.cursor, .workspaceWrite, "command cursor-agent --force --sandbox enabled -- "),
        ]

        for (provider, access, expectedPrefix) in cases {
            let input = AgentLaunchPlan.initialInput(
                provider: provider,
                access: access,
                model: nil,
                task: "do the thing"
            )
            #expect(input.hasPrefix(expectedPrefix))
            #expect(!input.contains("-m "))
            #expect(!input.contains("--model"))
        }
    }

    @Test("worker contract text matches the documented contract verbatim")
    func workerContractText() {
        #expect(AgentLaunchPlan.workerContract.contains(
            "- Work only in the current working directory unless the task explicitly says otherwise."
        ))
        #expect(AgentLaunchPlan.workerContract.contains(
            "- Continue until the assigned task is complete; run relevant tests when changes are made."
        ))
        #expect(AgentLaunchPlan.workerContract.contains(
            "- Do not ask the user routine implementation questions. Make a reasonable choice, record it, and continue."
        ))
        #expect(AgentLaunchPlan.workerContract.contains(
            "- End with a concise summary containing: findings or changed files, tests run and results, and remaining issues."
        ))
        #expect(!AgentLaunchPlan.workerContract.lowercased().contains("override"))
    }

    @Test("inherited mode flags replace the access-derived flags for every provider")
    func inheritedFlagsReplaceAccessFlags() {
        let cases: [(AgentWorkerProvider, [String], String)] = [
            (
                .claude,
                ["--permission-mode", "acceptEdits"],
                "command claude '--permission-mode' 'acceptEdits' -- "
            ),
            (
                .claude,
                ["--dangerously-skip-permissions"],
                "command claude '--dangerously-skip-permissions' -- "
            ),
            (
                .codex,
                ["-s", "workspace-write", "-a", "never"],
                "command codex '-s' 'workspace-write' '-a' 'never' -- "
            ),
            (
                .cursor,
                ["--force", "--sandbox", "enabled"],
                "command cursor-agent '--force' '--sandbox' 'enabled' -- "
            ),
        ]

        for (provider, inherited, expectedPrefix) in cases {
            let input = AgentLaunchPlan.initialInput(
                provider: provider,
                access: .inherit,
                model: nil,
                inheritedModeArguments: inherited,
                task: "do the thing"
            )
            #expect(input.hasPrefix(expectedPrefix))
        }
    }

    @Test("codex appends -a never only when no inherited flag already governs approvals")
    func codexApprovalGuardOnlyWhenMissing() {
        let approvalGoverning: [[String]] = [
            ["-a", "on-failure"],
            ["--ask-for-approval", "on-failure"],
            ["--full-auto"],
            ["--yolo"],
            ["--dangerously-bypass-approvals-and-sandbox"],
        ]
        for flags in approvalGoverning {
            let input = AgentLaunchPlan.initialInput(
                provider: .codex,
                access: .inherit,
                model: nil,
                inheritedModeArguments: flags,
                task: "task"
            )
            #expect(!input.contains("-a never"))
        }

        let sandboxOnly = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .inherit,
            model: nil,
            inheritedModeArguments: ["-s", "workspace-write"],
            task: "task"
        )
        #expect(sandboxOnly.hasPrefix(
            "command codex '-s' 'workspace-write' -a never -- "
        ))
    }

    @Test("each inherited token is quoted individually")
    func inheritedTokensAreQuotedIndividually() {
        let input = AgentLaunchPlan.initialInput(
            provider: .claude,
            access: .inherit,
            model: nil,
            inheritedModeArguments: ["--permission-mode", "weird'mode"],
            task: "task"
        )
        #expect(input.contains(
            "'--permission-mode' 'weird'\\''mode' -- "
        ))
    }

    @Test("model flag still precedes inherited flags")
    func modelFlagPrecedesInheritedFlags() {
        let input = AgentLaunchPlan.initialInput(
            provider: .claude,
            access: .inherit,
            model: "sonnet",
            inheritedModeArguments: ["--permission-mode", "acceptEdits"],
            task: "task"
        )
        #expect(input.hasPrefix(
            "command claude --model 'sonnet' '--permission-mode' 'acceptEdits' -- "
        ))
    }

    @Test("nil inherited flags keep the existing command byte-for-byte")
    func nilInheritedFlagsKeepCommandUnchanged() {
        let withNilInherited = AgentLaunchPlan.initialInput(
            provider: .claude,
            access: .workspaceWrite,
            model: nil,
            inheritedModeArguments: nil,
            task: "task"
        )
        let withoutParameter = AgentLaunchPlan.initialInput(
            provider: .claude,
            access: .workspaceWrite,
            model: nil,
            task: "task"
        )
        #expect(withNilInherited == withoutParameter)
    }

    @Test("empty inherited flags keep the existing command byte-for-byte")
    func emptyInheritedFlagsKeepCommandUnchanged() {
        let withEmptyInherited = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            inheritedModeArguments: [],
            task: "task"
        )
        let withoutParameter = AgentLaunchPlan.initialInput(
            provider: .codex,
            access: .review,
            model: nil,
            task: "task"
        )
        #expect(withEmptyInherited == withoutParameter)
    }

    @Test(".inherit with no inherited flags falls back to the workspace-write flag set")
    func inheritWithNilInheritedFallsBackToWorkspaceWrite() {
        let cases: [(AgentWorkerProvider, String)] = [
            (.codex, "command codex -s workspace-write -a never -- "),
            (.claude, "command claude --permission-mode acceptEdits -- "),
            (.cursor, "command cursor-agent --force --sandbox enabled -- "),
        ]
        for (provider, expectedPrefix) in cases {
            let withNilInherited = AgentLaunchPlan.initialInput(
                provider: provider,
                access: .inherit,
                model: nil,
                inheritedModeArguments: nil,
                task: "do the thing"
            )
            #expect(withNilInherited.hasPrefix(expectedPrefix))

            let withEmptyInherited = AgentLaunchPlan.initialInput(
                provider: provider,
                access: .inherit,
                model: nil,
                inheritedModeArguments: [],
                task: "do the thing"
            )
            #expect(withEmptyInherited.hasPrefix(expectedPrefix))
        }
    }
}
