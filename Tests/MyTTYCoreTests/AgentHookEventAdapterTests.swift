import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent hook event adapters")
struct AgentHookEventAdapterTests {
    private let surfaceID = TerminalSurfaceID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000101"
    )!)
    private let occurredAt = Date(timeIntervalSince1970: 1_721_113_200)

    @Test("marks session start idle while an agent awaits its first prompt")
    func idleSessionStart() throws {
        for provider in [AgentProvider.codex, .claudeCode] {
            let event = try event(
                provider: provider,
                payload: """
                {
                  "session_id": "idle-session",
                  "hook_event_name": "SessionStart"
                }
                """
            )

            #expect(event?.kind == .idle)
        }
    }

    @Test("maps one Codex turn to a stable mytty run")
    func codexTurn() throws {
        let started = try event(
            provider: .codex,
            payload: """
            {
              "session_id": "0190f6f3-2a50-7000-8000-000000000001",
              "turn_id": "0190f6f3-2a50-7000-8000-000000000002",
              "cwd": "/Users/tester/project",
              "hook_event_name": "UserPromptSubmit",
              "prompt": "Implement the feature"
            }
            """
        )
        let approval = try event(
            provider: .codex,
            payload: """
            {
              "session_id": "0190f6f3-2a50-7000-8000-000000000001",
              "turn_id": "0190f6f3-2a50-7000-8000-000000000002",
              "cwd": "/Users/tester/project",
              "hook_event_name": "PermissionRequest",
              "tool_name": "Bash"
            }
            """
        )
        let succeeded = try event(
            provider: .codex,
            payload: """
            {
              "session_id": "0190f6f3-2a50-7000-8000-000000000001",
              "turn_id": "0190f6f3-2a50-7000-8000-000000000002",
              "cwd": "/Users/tester/project",
              "hook_event_name": "Stop"
            }
            """
        )

        #expect(started?.kind == .started)
        #expect(
            started?.sessionID
                == "0190f6f3-2a50-7000-8000-000000000001"
        )
        #expect(approval?.kind == .approvalRequested)
        #expect(approval?.message == "Bash requires approval")
        #expect(succeeded?.kind == .succeeded)
        #expect(started?.runID == approval?.runID)
        #expect(approval?.runID == succeeded?.runID)
    }

    @Test("maps Codex tool completion back to running")
    func codexToolCompletion() throws {
        let event = try event(
            provider: .codex,
            payload: """
            {
              "session_id": "codex-session",
              "turn_id": "b838a20c-22ea-43be-a40a-1166424a70db",
              "hook_event_name": "PostToolUse",
              "tool_name": "Bash"
            }
            """
        )

        #expect(event?.kind == .running)
    }

    @Test("maps Claude notifications and completion to one prompt")
    func claudePrompt() throws {
        let started = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "cwd": "/Users/tester/project",
              "hook_event_name": "UserPromptSubmit",
              "prompt": "Review this change"
            }
            """
        )
        let input = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "cwd": "/Users/tester/project",
              "hook_event_name": "Notification",
              "notification_type": "agent_needs_input",
              "message": "Choose a migration strategy"
            }
            """
        )
        let succeeded = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "cwd": "/Users/tester/project",
              "hook_event_name": "Stop"
            }
            """
        )

        #expect(started?.kind == .started)
        #expect(started?.sessionID == "claude-session")
        #expect(input?.kind == .inputRequested)
        #expect(input?.message == "Choose a migration strategy")
        #expect(succeeded?.kind == .succeeded)
        #expect(started?.runID == input?.runID)
        #expect(input?.runID == succeeded?.runID)
    }

    @Test("maps Claude session exit to a disconnected run")
    func claudeSessionEnd() throws {
        let event = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "cwd": "/Users/tester/project",
              "hook_event_name": "SessionEnd",
              "reason": "exit"
            }
            """
        )

        #expect(event?.kind == .disconnected)
    }

    @Test("waits for a complete Claude tool batch before returning to running")
    func claudeCodeToolCompletion() throws {
        for hookEventName in ["PostToolUse", "PostToolUseFailure"] {
            let event = try event(
                provider: .claudeCode,
                payload: """
                {
                  "session_id": "claude-session",
                  "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
                  "hook_event_name": "\(hookEventName)",
                  "tool_name": "Bash"
                }
                """
            )

            #expect(event == nil)
        }

        let batch = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "PostToolBatch"
            }
            """
        )

        #expect(batch?.kind == .running)
    }

    @Test("maps OpenCode plugin events with the supplied turn identifier")
    func openCodeTurn() throws {
        let started = try event(
            provider: .openCode,
            payload: """
            {
              "run_id": "msg_user_01",
              "event": {
                "type": "message.updated",
                "properties": {
                  "info": {
                    "id": "msg_user_01",
                    "sessionID": "ses_01",
                    "role": "user"
                  }
                }
              }
            }
            """
        )
        let approval = try event(
            provider: .openCode,
            payload: """
            {
              "run_id": "msg_user_01",
              "event": {
                "type": "permission.asked",
                "properties": {
                  "sessionID": "ses_01",
                  "title": "Run git push"
                }
              }
            }
            """
        )
        let failed = try event(
            provider: .openCode,
            payload: """
            {
              "run_id": "msg_user_01",
              "event": {
                "type": "session.error",
                "properties": {
                  "sessionID": "ses_01",
                  "error": { "data": { "message": "Provider unavailable" } }
                }
              }
            }
            """
        )
        let resumed = try event(
            provider: .openCode,
            payload: """
            {
              "run_id": "msg_user_01",
              "event": {
                "type": "permission.replied",
                "properties": {
                  "sessionID": "ses_01",
                  "requestID": "per_01",
                  "reply": "once"
                }
              }
            }
            """
        )

        #expect(started?.kind == .started)
        #expect(started?.sessionID == "ses_01")
        #expect(approval?.kind == .approvalRequested)
        #expect(approval?.message == "Run git push")
        #expect(failed?.kind == .failed)
        #expect(failed?.message == "Provider unavailable")
        #expect(resumed?.kind == .running)
        #expect(started?.runID == approval?.runID)
        #expect(approval?.runID == failed?.runID)
    }

    @Test("maps Antigravity lifecycle payloads using the conversation identifier")
    func antigravityConversation() throws {
        let running = try event(
            provider: .antigravity,
            payload: """
            {
              "conversationId": "ag-conversation-01",
              "invocationNum": 0,
              "initialNumSteps": 0,
              "workspacePaths": ["/Users/tester/project"]
            }
            """
        )
        let succeeded = try event(
            provider: .antigravity,
            payload: """
            {
              "conversationId": "ag-conversation-01",
              "executionNum": 1,
              "terminationReason": "model_stop",
              "error": "",
              "fullyIdle": true
            }
            """
        )
        let failed = try event(
            provider: .antigravity,
            payload: """
            {
              "conversationId": "ag-conversation-02",
              "executionNum": 1,
              "terminationReason": "error",
              "error": "Model unavailable",
              "fullyIdle": true
            }
            """
        )

        #expect(running?.kind == .running)
        #expect(running?.sessionID == "ag-conversation-01")
        #expect(succeeded?.kind == .succeeded)
        #expect(failed?.kind == .failed)
        #expect(failed?.message == "Model unavailable")
        #expect(running?.runID == succeeded?.runID)
    }

    @Test("maps a Cursor generation from prompt submission through stop")
    func cursorGeneration() throws {
        let started = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "beforeSubmitPrompt",
              "prompt": "Implement the feature"
            }
            """
        )
        let running = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "postToolUse",
              "tool_name": "Shell"
            }
            """
        )
        let failed = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "stop",
              "status": "error",
              "error": "Command failed",
              "loop_count": 0
            }
            """
        )

        #expect(started?.kind == .started)
        #expect(started?.sessionID == "cursor-conversation-01")
        #expect(running?.kind == .running)
        #expect(failed?.kind == .failed)
        #expect(failed?.message == "Command failed")
        #expect(started?.runID == running?.runID)
        #expect(running?.runID == failed?.runID)
    }

    @Test("accepts the Cursor CLI session identifier alias")
    func cursorCLISessionIdentifier() throws {
        let event = try event(
            provider: .cursor,
            payload: """
            {
              "session_id": "cursor-session-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "beforeSubmitPrompt",
              "prompt": "Implement the feature"
            }
            """
        )

        #expect(event?.kind == .started)
        #expect(event?.sessionID == "cursor-session-01")
    }

    @Test("uses a deterministic event identifier for hook retries")
    func retryIdentity() throws {
        let payload = """
        {
          "session_id": "claude-session",
          "prompt_id": "e2a0d23f-1de2-426a-9d14-ae1979787a7e",
          "cwd": "/Users/tester/project",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash"
        }
        """

        let first = try event(provider: .claudeCode, payload: payload)
        let retry = try AgentHookEventAdapter.makeEvent(
            provider: .claudeCode,
            payload: Data(payload.utf8),
            surfaceID: surfaceID,
            occurredAt: occurredAt.addingTimeInterval(30)
        )

        #expect(first?.id == retry?.id)
        #expect(first?.occurredAt != retry?.occurredAt)
    }

    @Test("ignores provider events that do not affect agent state")
    func ignoresUnrelatedEvents() throws {
        let event = try event(
            provider: .openCode,
            payload: """
            {
              "run_id": "msg_user_01",
              "event": {
                "type": "file.edited",
                "properties": { "file": "README.md" }
              }
            }
            """
        )

        #expect(event == nil)
    }

    @Test("ends the hook-reported run when the user interrupts it")
    func interruptionEndsTheHookRun() throws {
        let promptID = "1d97fd10-721e-4d85-bf79-c63b502fa365"
        let started = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "\(promptID)",
              "hook_event_name": "UserPromptSubmit",
              "prompt": "Review this change"
            }
            """
        )
        let interrupted = AgentHookEventAdapter.interruptionEvent(
            provider: .claudeCode,
            runKey: promptID,
            interruptionKey: "msg_01",
            sessionID: "claude-session",
            surfaceID: surfaceID,
            occurredAt: occurredAt.addingTimeInterval(5)
        )

        #expect(interrupted.kind == .idle)
        #expect(interrupted.runID == started?.runID)

        let startedEvent = try #require(started)
        let runs = AgentEventReducer.reduce([startedEvent, interrupted])
        #expect(runs[interrupted.runID]?.state == .idle)

        // Re-detecting the same interrupt must not produce a second event…
        #expect(
            AgentHookEventAdapter.interruptionEvent(
                provider: .claudeCode,
                runKey: promptID,
                interruptionKey: "msg_01",
                sessionID: "claude-session",
                surfaceID: surfaceID,
                occurredAt: occurredAt.addingTimeInterval(9)
            ).id == interrupted.id
        )

        // …but interrupting the same prompt again must end it again.
        #expect(
            AgentHookEventAdapter.interruptionEvent(
                provider: .claudeCode,
                runKey: promptID,
                interruptionKey: "msg_02",
                sessionID: "claude-session",
                surfaceID: surfaceID,
                occurredAt: occurredAt.addingTimeInterval(20)
            ).id != interrupted.id
        )
    }

    @Test("treats a Cursor stop with no status as a normal completion")
    func cursorStopWithoutStatusSucceeds() throws {
        let stopped = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "stop"
            }
            """
        )

        #expect(stopped?.kind == .succeeded)
        #expect(stopped?.hookName == "stop")
    }

    @Test("treats a Cursor stop with an unrecognized status as a completion")
    func cursorStopWithUnknownStatusSucceeds() throws {
        let stopped = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "stop",
              "status": "some-future-status"
            }
            """
        )

        #expect(stopped?.kind == .succeeded)
    }

    @Test("maps Cursor shell execution hooks to running with the command as message")
    func cursorShellExecutionHooks() throws {
        let before = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "beforeShellExecution",
              "command": "npm install"
            }
            """
        )
        let after = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "afterShellExecution",
              "command": "npm install"
            }
            """
        )

        #expect(before?.kind == .running)
        #expect(before?.hookName == "beforeShellExecution")
        #expect(before?.message == "npm install")
        #expect(after?.kind == .running)
        #expect(after?.hookName == "afterShellExecution")
        #expect(before?.runID == after?.runID)
    }

    @Test("maps Cursor preToolUse to running with tool_name as message and a sanitized tool_use_id")
    func cursorPreToolUse() throws {
        let preToolUse = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "preToolUse",
              "tool_name": "Delete",
              "tool_use_id": "call-1",
              "tool_input": { "file_path": "victim.txt" }
            }
            """
        )

        #expect(preToolUse?.kind == .running)
        #expect(preToolUse?.hookName == "preToolUse")
        #expect(preToolUse?.message == "Delete")
        #expect(preToolUse?.toolUseID == "call-1")
    }

    @Test("maps Cursor postToolUse and postToolUseFailure tool_use_id for pairing")
    func cursorPostToolUseCapturesToolUseID() throws {
        let postToolUse = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "postToolUse",
              "tool_name": "Grep",
              "tool_use_id": "call-2",
              "duration": 12
            }
            """
        )
        let postToolUseFailure = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "postToolUseFailure",
              "tool_name": "Delete",
              "tool_use_id": "call-3",
              "duration": 8
            }
            """
        )

        #expect(postToolUse?.toolUseID == "call-2")
        #expect(postToolUseFailure?.toolUseID == "call-3")
    }

    @Test("strips control characters from a Cursor tool_use_id instead of rejecting it")
    func cursorToolUseIDStripsControlCharacters() throws {
        // Real payloads have been observed with an embedded newline in
        // tool_use_id, e.g. "call-...-1\nfc_..._1" — unlike session
        // identifiers, this must not make the identifier nil, since
        // preToolUse/postToolUse pairing depends on it.
        let preToolUse = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "preToolUse",
              "tool_name": "Delete",
              "tool_use_id": "call-abc-1\\nfc_def_1"
            }
            """
        )

        #expect(preToolUse?.toolUseID == "call-abc-1fc_def_1")
    }

    @Test("truncates an overlong Cursor tool_use_id to 256 bytes")
    func cursorToolUseIDTruncatesToLengthLimit() throws {
        let overlong = String(repeating: "a", count: 300)
        let preToolUse = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "preToolUse",
              "tool_name": "Delete",
              "tool_use_id": "\(overlong)"
            }
            """
        )

        #expect(preToolUse?.toolUseID?.utf8.count == 256)
    }

    @Test("builds a synthetic pending-approval event that lands on the given run")
    func pendingApprovalEventTargetsTheGivenRun() throws {
        let preToolUse = try event(
            provider: .cursor,
            payload: """
            {
              "conversation_id": "cursor-conversation-01",
              "generation_id": "cursor-generation-01",
              "hook_event_name": "preToolUse",
              "tool_name": "Delete",
              "tool_use_id": "call-1"
            }
            """
        )
        let preToolUseEvent = try #require(preToolUse)

        let pending = AgentHookEventAdapter.pendingApprovalEvent(
            runID: preToolUseEvent.runID,
            toolUseID: "call-1",
            toolName: "Delete",
            sessionID: preToolUseEvent.sessionID,
            surfaceID: surfaceID,
            occurredAt: occurredAt.addingTimeInterval(10)
        )

        #expect(pending.kind == .approvalRequested)
        #expect(pending.runID == preToolUseEvent.runID)
        #expect(pending.message == "Delete requires approval")

        // Re-detecting the same stuck tool call must not produce a second
        // event, so `AttentionCenter` de-duplicates it on append.
        let pendingAgain = AgentHookEventAdapter.pendingApprovalEvent(
            runID: preToolUseEvent.runID,
            toolUseID: "call-1",
            toolName: "Delete",
            sessionID: preToolUseEvent.sessionID,
            surfaceID: surfaceID,
            occurredAt: occurredAt.addingTimeInterval(15)
        )
        #expect(pending.id == pendingAgain.id)

        let runs = AgentEventReducer.reduce([preToolUseEvent, pending])
        #expect(runs[preToolUseEvent.runID]?.state == .waitingApproval)
    }

    private func event(
        provider: AgentProvider,
        payload: String
    ) throws -> AgentEvent? {
        try AgentHookEventAdapter.makeEvent(
            provider: provider,
            payload: Data(payload.utf8),
            surfaceID: surfaceID,
            occurredAt: occurredAt
        )
    }
}
