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
        workingDirectory: String? = "/work/repo",
        task: String = "do the thing"
    ) -> String {
        AgentLaunchPlan.initialInput(
            provider: .antigravity,
            access: access,
            model: model,
            reasoningEffort: effort,
            inheritedModeArguments: inherited,
            workingDirectory: workingDirectory,
            task: task
        )
    }

    /// The arguments `agy` really receives: the launch line is run by
    /// `/bin/sh` with `agy` replaced by a function that prints its argv, so
    /// quoting bugs show up here exactly as they would in the pane.
    private func argv(_ input: String) throws -> [String] {
        let line = String(
            command(input).dropFirst("command ".count)
        ).trimmingCharacters(in: .newlines)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "agy() { for a in \"$@\"; do printf '%s\\0' \"$a\"; done; }; " + line,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        var parts = text.components(separatedBy: "\0")
        parts.removeLast()
        return parts
    }

    private func settings(_ input: String) throws -> [String: Any] {
        let args = try argv(input)
        let index = try #require(args.firstIndex(of: "--settings"))
        let json = try JSONSerialization.jsonObject(
            with: Data(args[index + 1].utf8)
        )
        return try #require(json as? [String: Any])
    }

    private func allowRules(_ input: String) throws -> [String] {
        let permissions = try #require(
            try settings(input)["permissions"] as? [String: Any]
        )
        return try #require(permissions["allow"] as? [String])
    }

    private func command(_ input: String) -> String {
        String(input.dropFirst(AgentLaunchPlan.historySuppressionPrefix.count))
    }

    @Test("review launches in plan mode with only side-effect-free allow rules")
    func reviewUsesPlanMode() throws {
        let launch = input(access: .review)
        #expect(command(launch).hasPrefix("command agy --mode plan --settings "))
        let rules = try allowRules(launch)
        #expect(rules.contains("command(gh pr view)"))
        #expect(rules.contains("command(gh pr diff)"))
        #expect(rules.contains("command(gh api)"))
        #expect(rules.contains("command(mytty-ctl status)"))
        // `rg --pre <cmd>` runs arbitrary commands; `git diff|log|show
        // --output=<path>` writes files. agy matches the rule as a command
        // prefix, so those flags cannot be fenced off: drop the commands.
        for forbidden in [
            "rg", "git diff", "git log", "git show", "git", "gh",
            "git push", "swift", "make", "mv", "cp", "mytty-ctl",
        ] {
            #expect(!rules.contains("command(\(forbidden))"), "\(forbidden)")
        }
    }

    @Test("workspace-write launches in accept-edits mode with subcommand-scoped rules")
    func workspaceWriteUsesAcceptEdits() throws {
        let launch = input(access: .workspaceWrite)
        #expect(command(launch).hasPrefix("command agy --mode accept-edits --settings "))
        let rules = try allowRules(launch)
        for expected in [
            "command(git add)", "command(git commit)", "command(git diff)",
            "command(gh pr create)", "command(swift)", "command(make)",
            "command(mytty-ctl status)",
        ] {
            #expect(rules.contains(expected), "\(expected)")
        }
        // Irreversible or workspace-escaping operations stay at the prompt.
        for forbidden in [
            "git", "gh", "git push", "git reset", "gh pr merge", "gh api",
            "mv", "cp", "mytty-ctl", "rg",
        ] {
            #expect(!rules.contains("command(\(forbidden))"), "\(forbidden)")
        }
    }

    @Test("settings trust the working directory and are session-only JSON")
    func settingsTrustWorkingDirectory() throws {
        let object = try settings(input(access: .review))
        #expect(object["trustedWorkspaces"] as? [String] == ["/work/repo"])
        #expect(Set(object.keys) == ["trustedWorkspaces", "permissions"])
    }

    @Test("a working directory with quotes and backslashes cannot inject settings")
    func hostileWorkingDirectory() throws {
        let hostile = #"/tmp/x"],"permissions":{"allow":["command(git)"]},"y":["\z"#
        let object = try settings(input(access: .review, workingDirectory: hostile))
        #expect(object["trustedWorkspaces"] as? [String] == [hostile])
        #expect(Set(object.keys) == ["trustedWorkspaces", "permissions"])
        let rules = try allowRules(input(access: .review, workingDirectory: hostile))
        #expect(!rules.contains("command(git)"))
    }

    @Test("a working directory with a single quote or shell metacharacters stays one argument")
    func shellHostileWorkingDirectory() throws {
        let path = "/tmp/it's $(touch pwned) `x` ; y"
        let object = try settings(input(access: .review, workingDirectory: path))
        #expect(object["trustedWorkspaces"] as? [String] == [path])
    }

    @Test("without a working directory nothing is trusted but rules still apply")
    func noWorkingDirectory() throws {
        let object = try settings(input(access: .review, workingDirectory: nil))
        #expect(object["trustedWorkspaces"] == nil)
        #expect(object["permissions"] != nil)
    }

    @Test("the task is passed as the quoted initial interactive prompt")
    func taskUsesPromptInteractive() throws {
        let args = try argv(input(access: .review, task: "it's a task"))
        let index = try #require(args.firstIndex(of: "-i"))
        #expect(index == args.count - 2)
        #expect(args[index + 1].hasPrefix("it's a task"))
        #expect(args[index + 1].contains("Mytty worker contract:"))
    }

    @Test("a task starting with a dash stays a quoted value of -i")
    func dashTask() throws {
        let args = try argv(input(access: .review, task: "--help"))
        let index = try #require(args.firstIndex(of: "-i"))
        #expect(args[index + 1].hasPrefix("--help"))
    }

    @Test("model and reasoning effort lead the launch options")
    func modelAndEffort() throws {
        let args = try argv(input(
            access: .review,
            model: "gemini-4-argon",
            effort: .high
        ))
        #expect(Array(args.prefix(6)) == [
            "--model", "gemini-4-argon", "--effort", "high", "--mode", "plan",
        ])
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

    @Test("inherited flags replace the mode flag and keep trust")
    func inheritedFlags() throws {
        let launch = input(
            access: .inherit,
            inherited: ["--mode", "accept-edits", "--sandbox"]
        )
        #expect(command(launch).hasPrefix(
            "command agy '--mode' 'accept-edits' '--sandbox' --settings "
        ))
        #expect(!command(launch).contains("--mode plan"))
        #expect(try settings(launch)["trustedWorkspaces"] as? [String] == ["/work/repo"])
    }

    @Test("inheriting plan mode keeps the read-only allow rules")
    func inheritedPlanIsReadOnly() throws {
        for flags in [["--mode", "plan"], ["--sandbox", "--mode", "plan"]] {
            let rules = try allowRules(input(access: .inherit, inherited: flags))
            #expect(rules.contains("command(gh pr view)"))
            #expect(!rules.contains("command(git add)"))
            #expect(!rules.contains("command(git commit)"))
            #expect(!rules.contains("command(swift)"))
            #expect(!rules.contains("command(make)"))
        }
    }

    @Test("inheriting a writable mode gets the workspace-write rules")
    func inheritedWritableMode() throws {
        for flags in [
            ["--mode", "accept-edits"], ["--mode", "auto"],
            ["--dangerously-skip-permissions"], ["--sandbox"],
        ] {
            let rules = try allowRules(input(access: .inherit, inherited: flags))
            #expect(rules.contains("command(git commit)"), "\(flags)")
        }
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
