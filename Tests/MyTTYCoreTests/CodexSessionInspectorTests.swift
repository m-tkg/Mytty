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

    @Test("collects recent user prompts from event messages")
    func recentUserPrompts() {
        let data = Data("""
        {"type":"session_meta","payload":{"session_id":"s"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"refactor the parser","kind":"plain"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{}}}
        {"type":"event_msg","payload":{"type":"user_message","message":"now add tests"}}
        """.utf8)

        #expect(
            CodexSessionInspector.recentUserPrompts(from: data, limit: 5)
                == ["refactor the parser", "now add tests"]
        )
    }

    @Test("skips instruction and environment context messages")
    func recentUserPromptsSkipsInjectedContent() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"user_message","message":"<user_instructions>be terse</user_instructions>"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"<environment_context>cwd: /repo</environment_context>"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"instructions","kind":"user_instructions"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"ship the release"}}
        """.utf8)

        #expect(
            CodexSessionInspector.recentUserPrompts(from: data, limit: 5)
                == ["ship the release"]
        )
    }

    @Test("falls back to response items when no event messages exist")
    func recentUserPromptsFromResponseItems() {
        let data = Data("""
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"debug the crash"}]}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done"}]}}
        not json
        """.utf8)

        #expect(
            CodexSessionInspector.recentUserPrompts(from: data, limit: 5)
                == ["debug the crash"]
        )
    }

    @Test("keeps only the most recent prompts and sanitizes them")
    func recentUserPromptsLimitAndSanitize() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"user_message","message":"first"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"second\\n\\twith   spaces"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"third"}}
        """.utf8)

        #expect(
            CodexSessionInspector.recentUserPrompts(from: data, limit: 2)
                == ["second with spaces", "third"]
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
