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

    @Test("identifies shell command names, including login-shell form")
    func shellCommandNameDetection() {
        for name in ["zsh", "bash", "fish", "sh", "dash", "tcsh", "csh", "ksh", "nu", "pwsh"] {
            #expect(TerminalAgentProcessDetector.isShellCommandName(name))
        }
        #expect(TerminalAgentProcessDetector.isShellCommandName("-zsh"))
        #expect(TerminalAgentProcessDetector.isShellCommandName("-bash"))
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
