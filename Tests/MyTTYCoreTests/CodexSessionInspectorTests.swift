import Darwin
import Foundation
import Testing

@testable import MyTTYCore

@Suite("Codex session inspection")
struct CodexSessionInspectorTests {
    @Test("reads the session identifier from Codex transcript metadata")
    func metadata() {
        let current = Data("""
        {"type":"session_meta","payload":{"id":"thread-id","session_id":"codex-session-id","cwd":"/repo"}}
        {"type":"event_msg","payload":{}}
        """.utf8)
        let legacy = Data("""
        {"type":"session_meta","payload":{"id":"legacy-session-id"}}
        """.utf8)

        #expect(
            CodexSessionInspector.sessionID(from: current)
                == "codex-session-id"
        )
        #expect(
            CodexSessionInspector.sessionID(from: legacy)
                == "legacy-session-id"
        )
        #expect(CodexSessionInspector.sessionID(from: Data("{}".utf8)) == nil)
    }

    @Test("reads the current model and remaining context from a transcript")
    func sessionStatus() {
        let data = Data("""
        {"type":"session_meta","payload":{"session_id":"codex-session-id"}}
        {"type":"turn_context","payload":{"model":"gpt-5.4-mini"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":64500},"model_context_window":258000}}}
        """.utf8)

        #expect(
            CodexSessionInspector.status(from: data)
                == AgentSessionStatus(
                    sessionID: "codex-session-id",
                    modelName: "gpt-5.4-mini",
                    contextRemainingPercent: 75
                )
        )
    }

    @Test("finds the transcript opened by the exact Codex process")
    func openTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome
            .appendingPathComponent("sessions/2026/07/17", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = sessions.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"session_meta","payload":{"session_id":"open-session-id"}}
        """.write(to: transcript, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forReadingFrom: transcript)
        defer { try? handle.close() }

        #expect(
            CodexSessionInspector.sessionID(
                processID: getpid(),
                codexHome: codexHome
            ) == "open-session-id"
        )
    }

    @Test("prefers the process-bound identifier and preserves hook fallback")
    func selection() {
        #expect(
            AgentSessionIDSelection.resolve(
                processBound: "process-session",
                hook: "hook-session"
            ) == "process-session"
        )
        #expect(
            AgentSessionIDSelection.resolve(
                processBound: nil,
                hook: "hook-session"
            ) == "hook-session"
        )
    }
}
