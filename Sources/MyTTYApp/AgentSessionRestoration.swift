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
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
