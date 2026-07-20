import Foundation
import Testing

@testable import MyTTYCore

@Suite("Claude Code session inspection")
struct ClaudeCodeSessionInspectorTests {
    @Test("reads the current model and remaining context from a transcript")
    func sessionStatus() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-sonnet-5","usage":{"input_tokens":40000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":5000,"output_tokens":900}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data)
                == AgentSessionStatus(
                    sessionID: "claude-session-id",
                    modelName: "claude-sonnet-5",
                    contextRemainingPercent: 75
                )
        )
    }

    @Test("uses a 1,000,000 token window for [1m] models")
    func largeContextWindow() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-fable-5[1m]","usage":{"input_tokens":250000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data)
                == AgentSessionStatus(
                    sessionID: "claude-session-id",
                    modelName: "claude-fable-5[1m]",
                    contextRemainingPercent: 75
                )
        )
    }

    @Test("ignores sidechain rows and rows without usage, taking the last valid row")
    func ignoresInvalidRows() {
        let data = Data("""
        {"type":"assistant","isSidechain":true,"sessionId":"sidechain-session","message":{"model":"claude-sidechain","usage":{"input_tokens":1000}}}
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-no-usage"}}
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-sonnet-5","usage":{"input_tokens":100000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data)
                == AgentSessionStatus(
                    sessionID: "claude-session-id",
                    modelName: "claude-sonnet-5",
                    contextRemainingPercent: 50
                )
        )
    }

    @Test("does not fail on malformed JSON lines mixed into the transcript")
    func toleratesMalformedLines() {
        let data = Data("""
        not json at all
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-sonnet-5","usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        {"broken
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data)
                == AgentSessionStatus(
                    sessionID: "claude-session-id",
                    modelName: "claude-sonnet-5",
                    contextRemainingPercent: 75
                )
        )
    }

    @Test("uses a 1,000,000 token window for Mythos-class models")
    func mythosContextWindow() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-fable-5","usage":{"input_tokens":2,"cache_creation_input_tokens":63,"cache_read_input_tokens":559199,"output_tokens":1181}}}
        """.utf8)

        let status = ClaudeCodeSessionInspector.status(from: data)
        #expect(status?.modelName == "claude-fable-5")
        // ~559k used against the 1M estimate, not pinned to 0% by the
        // 200k default.
        #expect(status.flatMap(\.contextRemainingPercent).map { $0 > 40 && $0 < 50 } == true)
    }

    @Test("clamps to 0% once usage exceeds the context window")
    func clampsAtZero() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-sonnet-5","usage":{"input_tokens":250000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data)?.contextRemainingPercent == 0
        )
    }

    @Test("finds a transcript by session ID and falls back to the cwd slug")
    func transcriptLookup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeHome = root.appendingPathComponent(".claude", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workingDirectory = URL(
            fileURLWithPath: "/Users/masaki/git/github.com/m-tkg/mytty",
            isDirectory: true
        )
        let slug = ClaudeCodeSessionInspector.slug(for: workingDirectory)
        #expect(slug == "-Users-masaki-git-github-com-m-tkg-mytty")

        let projectDirectory = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        let transcript = projectDirectory
            .appendingPathComponent("session-by-slug.jsonl")
        try """
        {"type":"assistant","isSidechain":false,"sessionId":"session-by-slug","message":{"model":"claude-fable-5","usage":{"input_tokens":10000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.write(to: transcript, atomically: true, encoding: .utf8)

        #expect(
            ClaudeCodeSessionInspector.status(
                sessionID: nil,
                workingDirectory: workingDirectory,
                claudeHome: claudeHome
            )?.sessionID == "session-by-slug"
        )

        let otherProjectDirectory = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-some-other-project", isDirectory: true)
        try FileManager.default.createDirectory(
            at: otherProjectDirectory,
            withIntermediateDirectories: true
        )
        let bySessionID = otherProjectDirectory
            .appendingPathComponent("looked-up-by-id.jsonl")
        try """
        {"type":"assistant","isSidechain":false,"sessionId":"looked-up-by-id","message":{"model":"claude-fable-5","usage":{"input_tokens":20000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.write(to: bySessionID, atomically: true, encoding: .utf8)

        #expect(
            ClaudeCodeSessionInspector.status(
                sessionID: "looked-up-by-id",
                workingDirectory: nil,
                claudeHome: claudeHome
            )?.sessionID == "looked-up-by-id"
        )

        // A hook can report a session whose transcript is not written yet;
        // the cwd slug lookup must still provide a result.
        #expect(
            ClaudeCodeSessionInspector.status(
                sessionID: "not-written-yet",
                workingDirectory: workingDirectory,
                claudeHome: claudeHome
            )?.sessionID == "session-by-slug"
        )
    }

    @Test("reports the prompt of a run the user interrupted")
    func interruptedPrompt() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","sessionId":"s","message":{"model":"claude-fable-5","usage":{"input_tokens":1000}}}
        {"type":"user","promptId":"prompt-1","interruptedMessageId":"msg_01","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.interruption(from: data)
                == ClaudeCodeInterruption(
                    promptID: "prompt-1",
                    messageID: "msg_01"
                )
        )
    }

    @Test("stops reporting an interrupt once the next prompt starts")
    func interruptFollowedByNewPrompt() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","interruptedMessageId":"msg_01","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
        {"type":"user","promptId":"prompt-2","message":{"role":"user","content":"try again"}}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.interruption(from: data) == nil)
    }

    @Test("ignores sidechain interrupts and rows without a prompt")
    func interruptIgnoresUnrelatedRows() {
        let sidechain = Data("""
        {"type":"user","isSidechain":true,"promptId":"prompt-1","interruptedMessageId":"msg_01","message":{"role":"user","content":"x"}}
        """.utf8)
        #expect(
            ClaudeCodeSessionInspector.interruption(from: sidechain) == nil
        )

        let noPrompt = Data("""
        not json
        {"type":"user","interruptedMessageId":"msg_01","message":{"role":"user","content":"x"}}
        """.utf8)
        #expect(
            ClaudeCodeSessionInspector.interruption(from: noPrompt) == nil
        )
    }

    @Test("a completed prompt is not reported as interrupted")
    func completedPromptIsNotInterrupted() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","sessionId":"s","message":{"model":"claude-fable-5","usage":{"input_tokens":1000}}}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.interruption(from: data) == nil)
    }
}
