import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Agent session restoration")
struct AgentSessionRestorationTests {
    @Test("builds a safe resume command for every supported agent")
    func resumeCommands() {
        let expected: [(AgentResumeKind, String)] = [
            (.codex, "command codex resume -- 'session id'\n"),
            (.claudeCode, "command claude --resume='session id'\n"),
            (.openCode, "command opencode --session='session id'\n"),
            (.gemini, "command gemini --resume='session id'\n"),
            (.antigravity, "command agy --conversation='session id'\n"),
            (.cursor, "command cursor-agent --resume='session id'\n"),
        ]

        for (kind, command) in expected {
            #expect(
                AgentResumeLaunchPlan.initialInput(
                    for: AgentResumeDescriptor(
                        kind: kind,
                        sessionID: "session id"
                    )
                ) == command
            )
        }
        #expect(AgentResumeLaunchPlan.shellQuote("a'b") == "'a'\\''b'")
    }

    @Test("rejects session identifiers that cannot safely be restored")
    func invalidSessionIdentifiers() {
        for sessionID in ["", " leading", "trailing ", "line\nbreak"] {
            #expect(
                AgentResumeLaunchPlan.initialInput(
                    for: AgentResumeDescriptor(
                        kind: .codex,
                        sessionID: sessionID
                    )
                ) == nil
            )
        }
    }

    @Test("distinguishes Gemini CLI from Antigravity CLI")
    func antigravityExecutableKinds() {
        #expect(
            AgentResumeLaunchPlan.kind(
                provider: .antigravity,
                executablePath: "/opt/homebrew/bin/node",
                arguments: ["node", "/lib/gemini-cli/index.js"]
            ) == .gemini
        )
        #expect(
            AgentResumeLaunchPlan.kind(
                provider: .antigravity,
                executablePath: "/Users/tester/.local/bin/agy",
                arguments: ["agy"]
            ) == .antigravity
        )
        #expect(
            AgentResumeLaunchPlan.kind(
                provider: .claudeCode,
                executablePath: "/opt/homebrew/bin/node",
                arguments: ["node", "/lib/claude-code/cli.js"]
            ) == .claudeCode
        )
    }

    @Test("replaces stale resume metadata with currently active sessions")
    func restorationSnapshot() throws {
        let surface = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/repo", isDirectory: true),
            agentResume: AgentResumeDescriptor(
                kind: .claudeCode,
                sessionID: "stale-session"
            )
        )
        let tab = TabSession(initialSurface: surface)
        let session = WindowSession(
            frame: WindowFrame(x: 0, y: 0, width: 900, height: 600),
            tabs: [tab],
            selectedTabID: tab.id
        )
        let current = AgentResumeDescriptor(
            kind: .codex,
            sessionID: "current-session"
        )

        let active = AgentSessionRestoration.snapshot(
            session,
            activeResumes: [surface.id: current]
        )
        let cleared = AgentSessionRestoration.snapshot(
            session,
            activeResumes: [:]
        )

        guard case let .surface(activeSurface)? = active.selectedTab?.root,
              case let .surface(clearedSurface)? = cleared.selectedTab?.root
        else {
            Issue.record("Expected a single restored terminal surface")
            return
        }
        #expect(activeSurface.agentResume == current)
        #expect(clearedSurface.agentResume == nil)
    }
}
