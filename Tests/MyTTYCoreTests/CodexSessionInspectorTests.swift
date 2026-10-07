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

    // MARK: - Turn observation (Phase 2: transcript-derived turns)

    @Test("a task_started with no task_complete/turn_aborted yet reads as an active turn")
    func turnActive() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"agent_message","message":"working"}}
        """.utf8)

        #expect(
            CodexSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "turn-1", phase: .active)
        )
    }

    @Test("a task_complete after task_started completes the turn")
    func turnCompleted() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"done"}}
        """.utf8)

        #expect(
            CodexSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "turn-1", phase: .completed)
        )
    }

    @Test("a turn_aborted after task_started interrupts the turn")
    func turnAborted() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1","reason":"interrupted"}}
        """.utf8)

        #expect(
            CodexSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "turn-1", phase: .interrupted)
        )
    }

    @Test("a later task_started supersedes an earlier completed turn")
    func turnFollowedByNewTaskStarted() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}
        """.utf8)

        #expect(
            CodexSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "turn-2", phase: .active)
        )
    }

    @Test("malformed lines are skipped without breaking turn parsing")
    func turnToleratesMalformedLines() {
        let data = Data("""
        not json at all
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"broken
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        """.utf8)

        #expect(
            CodexSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "turn-1", phase: .completed)
        )
    }

    @Test("a tail with no task_started yields no turn")
    func turnNilWithoutTaskStarted() {
        let data = Data("""
        {"type":"event_msg","payload":{"type":"agent_message","message":"hi"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{}}}
        """.utf8)

        #expect(CodexSessionInspector.turn(from: data) == nil)
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

    // MARK: - Resume argument

    private static let sampleID = "01a113a2-d263-7b13-b24e-eec340025374"

    @Test("reads the session id from a codex resume command line")
    func resumedSessionID() {
        let id = Self.sampleID
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume", id]
            ) == id
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "-m", "gpt-5", "resume", "--no-daemon", id]
            ) == id
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume", id, "--yolo"]
            ) == id
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume", id.uppercased()]
            ) == id
        )
    }

    @Test("ignores resume arguments that are not a session id")
    func resumedSessionIDRejections() {
        let id = Self.sampleID
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume", "--last"]
            ) == nil
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume", "my-session-name"]
            ) == nil
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume"]
            ) == nil
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "resume", "--last", id]
            ) == nil
        )
        // The id has to follow the subcommand, not merely appear.
        #expect(
            CodexSessionInspector.resumedSessionID(arguments: ["codex", id])
                == nil
        )
        #expect(
            CodexSessionInspector.resumedSessionID(
                arguments: ["codex", "exec", "resume", "x", id]
            ) == nil
        )
        #expect(CodexSessionInspector.resumedSessionID(arguments: []) == nil)
    }

    // MARK: - Metadata lookup by session id

    private func uuidV7(at date: Date, variant: String = "a00") -> String {
        let milliseconds = UInt64(date.timeIntervalSince1970 * 1000)
        let hex = String(format: "%012llx", milliseconds)
        return "\(hex.prefix(8))-\(hex.suffix(4))-7\(variant)-8000-0123456789ab"
    }

    private func firstLine(
        id: String,
        cwd: String = "/work/repo",
        originator: String = "codex-tui",
        source: String = "\"vscode\"",
        threadSource: String? = "\"user\""
    ) -> String {
        let thread = threadSource.map { ",\"thread_source\":\($0)" } ?? ""
        return """
        {"type":"session_meta","payload":{"session_id":"\(id)","id":"\(id)","cwd":"\(cwd)","originator":"\(originator)","source":\(source)\(thread)}}
        """
    }

    private func makeHome(
        id: String,
        createdAt: Date,
        fileDayOffset: Int = 0,
        contents: String?
    ) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard let contents else { return home }
        let calendar = Calendar.current
        let day = calendar.date(
            byAdding: .day, value: fileDayOffset, to: createdAt
        )!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let directory = home
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", parts.year!))
            .appendingPathComponent(String(format: "%02d", parts.month!))
            .appendingPathComponent(String(format: "%02d", parts.day!))
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try (contents + "\n{\"type\":\"event_msg\",\"payload\":{}}\n").write(
            to: directory.appendingPathComponent(
                "rollout-2026-01-01T00-00-00-\(id).jsonl"
            ),
            atomically: true,
            encoding: .utf8
        )
        return home
    }

    @Test("finds a user TUI thread's metadata by session id")
    func metadataLookup() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let id = uuidV7(at: created)
        let home = try makeHome(
            id: id, createdAt: created, contents: firstLine(id: id)
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let metadata = try #require(
            CodexSessionInspector.metadata(sessionID: id, codexHome: home)
        )
        #expect(metadata.sessionID == id)
        #expect(metadata.workingDirectory.path == "/work/repo")
    }

    @Test("accepts a rollout filed under the adjacent day")
    func metadataLookupAdjacentDay() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let id = uuidV7(at: created)
        for offset in [-1, 1] {
            let home = try makeHome(
                id: id, createdAt: created, fileDayOffset: offset,
                contents: firstLine(id: id)
            )
            defer { try? FileManager.default.removeItem(at: home) }

            #expect(
                CodexSessionInspector.metadata(sessionID: id, codexHome: home)
                    != nil
            )
        }
    }

    @Test("does not look further than the adjacent days")
    func metadataLookupFarDay() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let id = uuidV7(at: created)
        let home = try makeHome(
            id: id, createdAt: created, fileDayOffset: 3,
            contents: firstLine(id: id)
        )
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(
            CodexSessionInspector.metadata(sessionID: id, codexHome: home)
                == nil
        )
    }

    @Test("returns nil for a missing rollout or a non-UUIDv7 id")
    func metadataLookupMissing() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let id = uuidV7(at: created)
        let home = try makeHome(id: id, createdAt: created, contents: nil)

        #expect(
            CodexSessionInspector.metadata(sessionID: id, codexHome: home)
                == nil
        )
        let v4 = "9f1b6a5e-1c2d-4e3f-8a4b-5c6d7e8f9a0b"
        let v4Home = try makeHome(
            id: v4, createdAt: created, contents: firstLine(id: v4)
        )
        defer { try? FileManager.default.removeItem(at: v4Home) }
        #expect(
            CodexSessionInspector.metadata(sessionID: v4, codexHome: v4Home)
                == nil
        )
        #expect(
            CodexSessionInspector.metadata(
                sessionID: "../../etc/passwd", codexHome: home
            ) == nil
        )
    }

    @Test("rejects a rollout whose first line does not match the session")
    func metadataLookupMismatch() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let id = uuidV7(at: created)
        let otherID = uuidV7(at: created, variant: "b00")
        let cases: [String] = [
            firstLine(id: otherID),
            "not json at all",
            "",
            "{\"type\":\"event_msg\",\"payload\":{}}",
            firstLine(id: id, cwd: "relative/path"),
            firstLine(id: id, cwd: "/work/\\u0007bell"),
        ]
        for contents in cases {
            let home = try makeHome(
                id: id, createdAt: created, contents: contents
            )
            defer { try? FileManager.default.removeItem(at: home) }

            #expect(
                CodexSessionInspector.metadata(sessionID: id, codexHome: home)
                    == nil
            )
        }
    }

    @Test("rejects threads that are not user-facing TUI threads")
    func metadataLookupThreadKinds() throws {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let id = uuidV7(at: created)
        let cases: [String] = [
            firstLine(id: id, originator: "codex_exec", source: "\"exec\"",
                      threadSource: nil),
            firstLine(id: id, originator: "Codex Desktop"),
            firstLine(id: id, threadSource: "\"subagent\""),
            firstLine(id: id, threadSource: nil),
            firstLine(
                id: id,
                source: "{\"subagent\":{\"thread_spawn\":{}}}",
                threadSource: "\"user\""
            ),
        ]
        for contents in cases {
            let home = try makeHome(
                id: id, createdAt: created, contents: contents
            )
            defer { try? FileManager.default.removeItem(at: home) }

            #expect(
                CodexSessionInspector.metadata(sessionID: id, codexHome: home)
                    == nil
            )
        }
        let cliHome = try makeHome(
            id: id, createdAt: created,
            contents: firstLine(id: id, source: "\"cli\"")
        )
        defer { try? FileManager.default.removeItem(at: cliHome) }
        #expect(
            CodexSessionInspector.metadata(sessionID: id, codexHome: cliHome)
                != nil
        )
    }
}
