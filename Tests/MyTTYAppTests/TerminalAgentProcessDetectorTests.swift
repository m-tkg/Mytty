import Darwin
import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Terminal agent process detector")
struct TerminalAgentProcessDetectorTests {
    @Test("reports only actively processing agents in a tab")
    func tabAgentActivity() {
        let ids = [TerminalSurfaceID(), TerminalSurfaceID(), TerminalSurfaceID()]
        let providers: [TerminalSurfaceID: AgentProvider] = [ids[1]: .codex]
        let processing: [TerminalSurfaceID: TerminalAgentLifecycle] = [
            ids[1]: TerminalAgentLifecycle(provider: .codex, state: .running),
        ]

        #expect(TerminalTabAgentActivity.isProcessing(
            surfaceIDs: [ids[0], ids[1]],
            foregroundProvidersBySurface: providers,
            lifecycleBySurface: processing
        ))
        #expect(!TerminalTabAgentActivity.isProcessing(
            surfaceIDs: [ids[0], ids[2]],
            foregroundProvidersBySurface: providers,
            lifecycleBySurface: processing
        ))

        for state in [
            AgentRunState.idle,
            AgentRunState.waitingInput,
            .waitingApproval,
            .succeeded,
            .failed,
            .disconnected,
        ] {
            #expect(!TerminalTabAgentActivity.isProcessing(
                surfaceIDs: [ids[1]],
                foregroundProvidersBySurface: providers,
                lifecycleBySurface: [
                    ids[1]: TerminalAgentLifecycle(
                        provider: .codex,
                        state: state
                    ),
                ]
            ))
        }

        #expect(!TerminalTabAgentActivity.isProcessing(
            surfaceIDs: [ids[1]],
            foregroundProvidersBySurface: providers,
            lifecycleBySurface: [
                ids[1]: TerminalAgentLifecycle(
                    provider: .claudeCode,
                    state: .running
                ),
            ]
        ))
    }

    @Test("detects supported agents from foreground process commands")
    func foregroundAgentDetection() {
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/Users/tester/.local/bin/codex",
            arguments: ["codex"]
        ) == .codex)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/opt/homebrew/bin/node",
            arguments: ["node", "/lib/@anthropic-ai/claude-code/cli.js"]
        ) == .claudeCode)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/opt/homebrew/bin/opencode",
            arguments: ["opencode"]
        ) == .openCode)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/opt/homebrew/bin/gemini",
            arguments: ["gemini"]
        ) == .antigravity)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/Users/tester/.local/bin/agy",
            arguments: ["agy"]
        ) == .antigravity)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/usr/local/bin/cursor-agent",
            arguments: ["cursor-agent"]
        ) == .cursor)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/bin/zsh",
            arguments: ["-zsh"]
        ) == nil)
    }

    @Test("falls back to the MYTTY_AGENT environment hint")
    func agentEnvironmentHint() {
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/usr/bin/ssh",
            arguments: ["ssh", "devbox"],
            environment: ["MYTTY_AGENT": "claude-code"]
        ) == .claudeCode)
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/usr/local/bin/docker",
            arguments: ["docker", "exec", "-it", "box", "codex"],
            environment: ["MYTTY_AGENT": "codex"]
        ) == .codex)

        // Real detection wins over a contradicting hint.
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/Users/tester/.local/bin/codex",
            arguments: ["codex"],
            environment: ["MYTTY_AGENT": "cursor"]
        ) == .codex)

        // Hints are normalized (trimmed, lowercased) before matching.
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/usr/bin/ssh",
            arguments: ["ssh"],
            environment: ["MYTTY_AGENT": " CODEX\n"]
        ) == .codex)

        // Only exact provider identifiers are accepted.
        for invalid in ["", "gpt5", "claude code", "claude-code\u{1B}[0m", "claude"] {
            #expect(TerminalAgentProcessDetector.provider(
                executablePath: "/usr/bin/ssh",
                arguments: ["ssh"],
                environment: ["MYTTY_AGENT": invalid]
            ) == nil, "hint \(invalid) should be rejected")
        }
        #expect(TerminalAgentProcessDetector.provider(
            executablePath: "/usr/bin/ssh",
            arguments: ["ssh"],
            environment: [:]
        ) == nil)
    }

    @Test("reads a running process's exec-time environment")
    func processEnvironment() {
        let environment = TerminalAgentProcessDetector.environment(
            processID: getpid()
        )
        #expect(environment["PATH"]?.isEmpty == false)
        #expect(TerminalAgentProcessDetector.environment(processID: 0).isEmpty)
        #expect(TerminalAgentProcessDetector.environment(processID: -1).isEmpty)
    }

    /// The bug this guards: a pane whose agent was started by a wrapper
    /// script has the shell in front and the agent as its child, so the pane
    /// was named after the shell (`bash`) and no session status was read.
    ///
    /// `exec -a claude sleep` stands in for a real agent: only the process's
    /// executable path and argv are examined, and no test may depend on an
    /// agent actually being installed on the machine.
    @Test("finds an agent launched by a wrapper script below the shell")
    func agentBelowAWrapperScript() async throws {
        let wrapper = Process()
        wrapper.executableURL = URL(fileURLWithPath: "/bin/sh")
        wrapper.arguments = ["-c", "exec -a claude /bin/sleep 30 & wait"]
        try wrapper.run()
        defer {
            wrapper.terminate()
            wrapper.waitUntilExit()
        }
        let wrapperPID = wrapper.processIdentifier

        var found: TerminalAgentProcessDetector.AgentProcess?
        for _ in 0..<100 {
            found = TerminalAgentProcessDetector.agentProcess(
                processID: wrapperPID
            )
            if found != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(found?.provider == .claudeCode)
        // The agent's own pid, not the wrapper's: the session inspectors and
        // the resume flags are read from it.
        #expect(found?.processID != wrapperPID)
        #expect(
            TerminalAgentProcessDetector.childProcessIDs(of: wrapperPID)
                .contains(found?.processID ?? -1)
        )
    }

    @Test("a shell with nothing under it runs no agent")
    func shellWithoutAnAgent() async throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "/bin/sleep 30"]
        try shell.run()
        defer {
            shell.terminate()
            shell.waitUntilExit()
        }
        try? await Task.sleep(for: .milliseconds(200))

        #expect(
            TerminalAgentProcessDetector.agentProcess(
                processID: shell.processIdentifier
            ) == nil
        )
        #expect(TerminalAgentProcessDetector.agentProcess(processID: 0) == nil)
        #expect(TerminalAgentProcessDetector.agentProcess(processID: -1) == nil)
    }

    @Test("identifies shell command names")
    func shellCommandNameDetection() {
        for name in ["zsh", "bash", "fish", "sh", "dash", "tcsh", "csh", "ksh", "nu", "pwsh"] {
            #expect(TerminalAgentProcessDetector.isShellCommandName(name))
        }
        #expect(!TerminalAgentProcessDetector.isShellCommandName("vim"))
        #expect(!TerminalAgentProcessDetector.isShellCommandName("claude"))
        #expect(!TerminalAgentProcessDetector.isShellCommandName(""))
    }

    @Test("resolves a running process's current working directory")
    func processWorkingDirectory() {
        let expected = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        #expect(TerminalAgentProcessDetector.workingDirectory(
            processID: getpid()
        )?.standardizedFileURL == expected)
        #expect(TerminalAgentProcessDetector.workingDirectory(processID: 0) == nil)
        #expect(TerminalAgentProcessDetector.workingDirectory(processID: -1) == nil)
    }

    @Test("prefers the agent's own working directory over the shell's")
    func workingDirectorySelection() {
        let agentDirectory = URL(fileURLWithPath: "/tmp/worktree", isDirectory: true)
        let shellDirectory = URL(fileURLWithPath: "/tmp/main-checkout", isDirectory: true)

        #expect(TerminalWorkingDirectorySelection.resolve(
            agentDirectory: agentDirectory,
            shellDirectory: shellDirectory
        ) == agentDirectory)
        #expect(TerminalWorkingDirectorySelection.resolve(
            agentDirectory: nil,
            shellDirectory: shellDirectory
        ) == shellDirectory)
        #expect(TerminalWorkingDirectorySelection.resolve(
            agentDirectory: nil,
            shellDirectory: nil
        ) == nil)
    }

    @Test("shows only the agent running in the foreground")
    func foregroundAgentDisplay() {
        #expect(TerminalAgentDisplay.resolve(
            foregroundProvider: nil
        ) == nil)
        #expect(TerminalAgentDisplay.resolve(
            foregroundProvider: .codex
        ) == TerminalAgentDisplay(provider: .codex))
        #expect(TerminalAgentDisplay.resolve(
            foregroundProvider: .codex
        ) == TerminalAgentDisplay(provider: .codex))
        #expect(TerminalAgentDisplay.resolve(
            foregroundProvider: .claudeCode
        ) == TerminalAgentDisplay(provider: .claudeCode))
    }
}
