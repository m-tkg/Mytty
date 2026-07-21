import Foundation
import MyTTYCore

enum AgentResumeLaunchPlan {
    static func initialInput(
        for descriptor: AgentResumeDescriptor?
    ) -> String? {
        guard let descriptor,
              isValid(sessionID: descriptor.sessionID)
        else { return nil }

        let sessionID = shellQuote(descriptor.sessionID)
        let command: String
        switch descriptor.kind {
        case .codex:
            command = "command codex resume -- \(sessionID)"
        case .claudeCode:
            command = "command claude --resume=\(sessionID)"
        case .openCode:
            command = "command opencode --session=\(sessionID)"
        case .gemini:
            command = "command gemini --resume=\(sessionID)"
        case .antigravity:
            command = "command agy --conversation=\(sessionID)"
        case .cursor:
            command = "command cursor-agent --resume=\(sessionID)"
        }
        return command + "\n"
    }

    static func kind(
        provider: AgentProvider,
        executablePath: String,
        arguments: [String]
    ) -> AgentResumeKind {
        switch provider {
        case .codex:
            .codex
        case .claudeCode:
            .claudeCode
        case .openCode:
            .openCode
        case .cursor:
            .cursor
        case .antigravity:
            isGeminiCLI(
                executablePath: executablePath,
                arguments: arguments
            ) ? .gemini : .antigravity
        }
    }

    static func shellQuote(_ value: String) -> String {
        ShellQuoting.quote(value)
    }

    private static func isValid(sessionID: String) -> Bool {
        !sessionID.isEmpty
            && sessionID.utf8.count <= 256
            && sessionID == sessionID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            && sessionID.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func isGeminiCLI(
        executablePath: String,
        arguments: [String]
    ) -> Bool {
        let tokens = [executablePath] + arguments
        let normalized = tokens.map { $0.lowercased() }
        let basenames = normalized.map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
        return basenames.contains("gemini")
            || basenames.contains("gemini-cli")
            || normalized.contains { $0.contains("/gemini-cli/") }
    }
}

/// Resolves the single transient `initialInput` a newly created surface is
/// launched with. There are exactly two sources — a caller-supplied agent
/// spawn command (`AgentJobCoordinator`) or a persisted resume descriptor
/// restored from a saved session — and they must never both apply to the
/// same surface: a resume descriptor is only ever set on a restored
/// surface, never on a freshly spawned one, and the spawn path always
/// passes `agentResume: nil`. The precondition documents and enforces that
/// invariant so future callers can't silently combine the two and end up
/// replaying a stale resume command instead of the intended spawn command
/// (or vice versa).
enum TerminalSurfaceLaunchInput {
    static func resolve(
        spawnInitialInput: String?,
        agentResume: AgentResumeDescriptor?
    ) -> String? {
        precondition(
            spawnInitialInput == nil || agentResume == nil,
            "Agent spawn initialInput must not be combined with a "
                + "persisted agent-resume descriptor."
        )
        return spawnInitialInput
            ?? AgentResumeLaunchPlan.initialInput(for: agentResume)
    }
}

enum AgentSessionRestoration {
    static func snapshot(
        _ session: WindowSession,
        activeResumes: [TerminalSurfaceID: AgentResumeDescriptor]
    ) -> WindowSession {
        var snapshot = session
        for surfaceID in session.tabs.flatMap(\.surfaceIDs) {
            try? snapshot.updateAgentResume(
                activeResumes[surfaceID],
                for: surfaceID
            )
        }
        return snapshot
    }
}
