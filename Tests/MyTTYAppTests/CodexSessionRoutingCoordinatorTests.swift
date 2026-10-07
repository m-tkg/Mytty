import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Codex session routing coordinator")
struct CodexSessionRoutingCoordinatorTests {
    private func event(
        session: String?,
        provider: AgentProvider = .codex,
        hook: String = "PostToolUse"
    ) -> AgentEvent {
        AgentEvent(
            runID: AgentRunID(),
            sessionID: session,
            surfaceID: TerminalSurfaceID(),
            provider: provider,
            kind: .started,
            occurredAt: Date(),
            hookName: hook
        )
    }

    @Test("routes by the session the pane's process holds open")
    @MainActor
    func processBound() {
        let a = CodexAgentPane(
            surfaceID: TerminalSurfaceID(), processID: 10, workingDirectory: nil
        )
        let b = CodexAgentPane(
            surfaceID: TerminalSurfaceID(), processID: 11, workingDirectory: nil
        )
        let coordinator = CodexSessionRoutingCoordinator(
            panes: { [a, b] },
            processBoundSessionID: { $0 == 10 ? "s1" : "s2" },
            arguments: { _ in [] },
            metadata: { _ in nil }
        )

        #expect(coordinator.surface(for: event(session: "s2")) == b.surfaceID)
        #expect(coordinator.surface(for: event(session: "s1")) == a.surfaceID)
    }

    @Test("falls back to the resume argument and reads argv once per process")
    @MainActor
    func resumeArgument() {
        let id = "01a113a2-d263-7b13-b24e-eec340025374"
        let pane = CodexAgentPane(
            surfaceID: TerminalSurfaceID(), processID: 10, workingDirectory: nil
        )
        var argvReads = 0
        let coordinator = CodexSessionRoutingCoordinator(
            panes: { [pane] },
            processBoundSessionID: { _ in nil },
            arguments: { _ in
                argvReads += 1
                return ["codex", "resume", id]
            },
            metadata: { _ in nil }
        )

        #expect(coordinator.surface(for: event(session: id)) == pane.surfaceID)
        #expect(coordinator.surface(for: event(session: id)) == pane.surfaceID)
        #expect(argvReads == 1)
    }

    @Test("claims by working directory and recognizes session-opening hooks")
    @MainActor
    func sessionStart() {
        let directory = URL(fileURLWithPath: "/tmp/mytty-routing/repo")
        let pane = CodexAgentPane(
            surfaceID: TerminalSurfaceID(),
            processID: 10,
            workingDirectory: directory
        )
        let coordinator = CodexSessionRoutingCoordinator(
            panes: { [pane] },
            processBoundSessionID: { _ in nil },
            arguments: { _ in [] },
            metadata: {
                CodexSessionMetadata(sessionID: $0, workingDirectory: directory)
            }
        )

        #expect(coordinator.surface(for: event(session: "s1")) == pane.surfaceID)
        #expect(coordinator.surface(for: event(session: "s2")) == nil)
        #expect(
            coordinator.surface(for: event(session: "s2", hook: "SessionStart"))
                == pane.surfaceID
        )
        #expect(coordinator.surface(for: event(session: "s3")) == nil)
        #expect(
            coordinator.surface(
                for: event(session: "s3", hook: "UserPromptSubmit")
            ) == pane.surfaceID
        )
    }

    @Test("returns nothing without a session id or for other providers")
    @MainActor
    func rejections() {
        let pane = CodexAgentPane(
            surfaceID: TerminalSurfaceID(), processID: 10, workingDirectory: nil
        )
        let coordinator = CodexSessionRoutingCoordinator(
            panes: { [pane] },
            processBoundSessionID: { _ in "s1" },
            arguments: { _ in [] },
            metadata: { _ in nil }
        )

        #expect(coordinator.surface(for: event(session: nil)) == nil)
        #expect(
            coordinator.surface(for: event(session: "s1", provider: .claudeCode))
                == nil
        )
    }
}
