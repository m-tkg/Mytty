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

    /// A transcript only ever names the normalized model, so the 1M window
    /// has to come from the selection the user configured.
    @Test("uses a 1,000,000 token window for a [1m] model selection")
    func largeContextWindowFromSelection() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-opus-5","usage":{"input_tokens":250000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data, selection: "opus[1m]")
                == AgentSessionStatus(
                    sessionID: "claude-session-id",
                    modelName: "claude-opus-5",
                    contextRemainingPercent: 75
                )
        )
    }

    @Test("keeps the 200k window without a [1m] selection")
    func defaultContextWindowWithoutSelection() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-opus-5","usage":{"input_tokens":100000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data)?
                .contextRemainingPercent == 50
        )
        #expect(
            ClaudeCodeSessionInspector.status(from: data, selection: "opus")?
                .contextRemainingPercent == 50
        )
    }

    @Test("keeps the 1,000,000 token window for natively large models")
    func nativeLargeContextWindowIgnoresSelection() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-fable-5","usage":{"input_tokens":250000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.status(from: data, selection: "fable")?
                .contextRemainingPercent == 75
        )
    }

    /// Claude Code rounds the used share, not the remainder.
    @Test("rounds the remaining percentage the way Claude Code does")
    func roundsLikeClaudeCode() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"sessionId":"claude-session-id","message":{"model":"claude-opus-5","usage":{"input_tokens":85000,"cache_creation_input_tokens":6806,"cache_read_input_tokens":0,"output_tokens":6301}}}
        """.utf8)

        // 91,806 / 200,000 = 45.903% used -> 46% used -> 54% remaining.
        #expect(
            ClaudeCodeSessionInspector.status(from: data)?
                .contextRemainingPercent == 54
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

    @Test("collects recent user prompts in chronological order")
    func recentUserPrompts() {
        let data = Data("""
        {"type":"user","message":{"role":"user","content":"fix the login bug"}}
        {"type":"assistant","isSidechain":false,"message":{"model":"m","usage":{"input_tokens":1}}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"add a regression test"}]}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.recentUserPrompts(from: data, limit: 5)
                == ["fix the login bug", "add a regression test"]
        )
    }

    @Test("keeps only the most recent prompts when over the limit")
    func recentUserPromptsLimit() {
        let data = Data("""
        {"type":"user","message":{"role":"user","content":"first"}}
        {"type":"user","message":{"role":"user","content":"second"}}
        {"type":"user","message":{"role":"user","content":"third"}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.recentUserPrompts(from: data, limit: 2)
                == ["second", "third"]
        )
    }

    @Test("skips sidechain, meta, tool-result, and interrupt rows")
    func recentUserPromptsSkipsNonPromptRows() {
        let data = Data("""
        {"type":"user","isSidechain":true,"message":{"role":"user","content":"sidechain prompt"}}
        {"type":"user","isMeta":true,"message":{"role":"user","content":"meta prompt"}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"tool output"}]}}
        {"type":"user","interruptedMessageId":"msg_01","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
        {"type":"assistant","isSidechain":false,"message":{"model":"m","usage":{"input_tokens":1}}}
        {"type":"user","message":{"role":"user","content":"the real prompt"}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.recentUserPrompts(from: data, limit: 5)
                == ["the real prompt"]
        )
    }

    @Test("skips command wrappers and system reminders")
    func recentUserPromptsSkipsInjectedContent() {
        let data = Data("""
        {"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}
        {"type":"user","message":{"role":"user","content":"<local-command-stdout></local-command-stdout>"}}
        {"type":"user","message":{"role":"user","content":"Caveat: The messages below were generated by the user while running local commands."}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>injected</system-reminder>"},{"type":"text","text":"deploy the app"}]}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.recentUserPrompts(from: data, limit: 5)
                == ["deploy the app"]
        )
    }

    @Test("collapses whitespace, strips control characters, and clamps length")
    func recentUserPromptsSanitizes() {
        let long = String(repeating: "a", count: 1_000)
        let data = Data("""
        {"type":"user","message":{"role":"user","content":"line one\\n\\n  line\\ttwo\\u0007"}}
        {"type":"user","message":{"role":"user","content":"\(long)"}}
        {"type":"user","message":{"role":"user","content":"   "}}
        not json at all
        """.utf8)

        let prompts = ClaudeCodeSessionInspector.recentUserPrompts(
            from: data,
            limit: 5
        )
        #expect(prompts.count == 2)
        #expect(prompts.first == "line one line two")
        #expect(prompts.last?.count == 400)
    }

    // MARK: - Turn observation (Phase 2: transcript-derived turns)

    @Test("a prompt with only tool_use replies so far reads as an active turn")
    func turnActive() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"tool_use"}}
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "prompt-1", phase: .active)
        )
    }

    @Test("an end_turn assistant reply after the prompt completes the turn")
    func turnCompletedByEndTurn() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"tool_use"}}
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"end_turn"}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "prompt-1", phase: .completed)
        )
    }

    @Test("a turn_duration system record after the prompt completes the turn")
    func turnCompletedByTurnDuration() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"end_turn"}}
        {"type":"system","subtype":"turn_duration","durationMs":1200}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "prompt-1", phase: .completed)
        )
    }

    @Test("tool_result user records are not mistaken for a new prompt")
    func turnIgnoresToolResultRecords() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"end_turn"}}
        {"type":"system","subtype":"turn_duration","durationMs":1200}
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"stray tool output"}]}}
        """.utf8)

        // The tool_result record doesn't start a new turn (still keyed on
        // prompt-1), but it does read as renewed activity on that turn.
        #expect(
            ClaudeCodeSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "prompt-1", phase: .active)
        )
    }

    @Test("a later real prompt supersedes an earlier completed turn")
    func turnFollowedByNewPrompt() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"end_turn"}}
        {"type":"system","subtype":"turn_duration","durationMs":1200}
        {"type":"user","promptId":"prompt-2","message":{"role":"user","content":"go again"}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.turn(from: data)
                == AgentTurnObservation(key: "prompt-2", phase: .active)
        )
    }

    @Test("a tail with no real user prompt yields no turn")
    func turnNilWithoutPrompt() {
        let data = Data("""
        {"type":"assistant","isSidechain":false,"message":{"stop_reason":"end_turn"}}
        {"type":"system","subtype":"turn_duration","durationMs":1200}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.turn(from: data) == nil)

        let sidechainOnly = Data("""
        {"type":"user","isSidechain":true,"promptId":"prompt-1","message":{"role":"user","content":"go"}}
        """.utf8)
        #expect(ClaudeCodeSessionInspector.turn(from: sidechainOnly) == nil)

        let toolResultOnly = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
        """.utf8)
        #expect(ClaudeCodeSessionInspector.turn(from: toolResultOnly) == nil)
    }

    // MARK: - Permission mode

    @Test("reads a standalone permission-mode record")
    func permissionModeFromStandaloneRecord() {
        let data = Data("""
        {"type":"permission-mode","permissionMode":"plan","sessionId":"s"}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.permissionMode(from: data) == "plan")
    }

    @Test("reads permissionMode carried on a user prompt record")
    func permissionModeFromUserRecord() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","permissionMode":"acceptEdits","message":{"role":"user","content":"go"}}
        """.utf8)

        #expect(
            ClaudeCodeSessionInspector.permissionMode(from: data)
                == "acceptEdits"
        )
    }

    @Test("the later of a standalone and a user record wins")
    func permissionModeLatestRecordWins() {
        let standaloneFirst = Data("""
        {"type":"permission-mode","permissionMode":"plan","sessionId":"s"}
        {"type":"user","promptId":"prompt-1","permissionMode":"acceptEdits","message":{"role":"user","content":"go"}}
        """.utf8)
        #expect(
            ClaudeCodeSessionInspector.permissionMode(from: standaloneFirst)
                == "acceptEdits"
        )

        let userFirst = Data("""
        {"type":"user","promptId":"prompt-1","permissionMode":"acceptEdits","message":{"role":"user","content":"go"}}
        {"type":"permission-mode","permissionMode":"plan","sessionId":"s"}
        """.utf8)
        #expect(
            ClaudeCodeSessionInspector.permissionMode(from: userFirst)
                == "plan"
        )
    }

    @Test("an unrecognized mode value is treated as nil")
    func permissionModeUnknownValueYieldsNil() {
        let data = Data("""
        {"type":"permission-mode","permissionMode":"yolo-mode","sessionId":"s"}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.permissionMode(from: data) == nil)
    }

    @Test("a mode value with a control character is treated as nil")
    func permissionModeControlCharacterYieldsNil() {
        let data = Data("""
        {"type":"permission-mode","permissionMode":"pla\\u0007n","sessionId":"s"}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.permissionMode(from: data) == nil)
    }

    @Test("an invalid later record does not clobber an earlier valid one")
    func permissionModeInvalidLaterRecordKeepsEarlierValue() {
        let data = Data("""
        {"type":"permission-mode","permissionMode":"plan","sessionId":"s"}
        {"type":"permission-mode","permissionMode":"not-a-real-mode","sessionId":"s"}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.permissionMode(from: data) == "plan")
    }

    @Test("a sidechain permission-mode record is ignored")
    func permissionModeIgnoresSidechain() {
        let data = Data("""
        {"type":"permission-mode","isSidechain":true,"permissionMode":"plan","sessionId":"s"}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.permissionMode(from: data) == nil)
    }

    @Test("no permission-mode record at all yields nil")
    func permissionModeAbsentYieldsNil() {
        let data = Data("""
        {"type":"user","promptId":"prompt-1","message":{"role":"user","content":"go"}}
        {"type":"assistant","isSidechain":false,"promptId":"prompt-1","message":{"stop_reason":"end_turn"}}
        """.utf8)

        #expect(ClaudeCodeSessionInspector.permissionMode(from: data) == nil)
    }
}
