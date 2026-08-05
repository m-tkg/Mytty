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
        #expect(approval?.toolName == "Bash")
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

    // MARK: - Background agent wait (Claude Code Stop)

    @Test("keeps a run open while one background subagent is still in flight")
    func stopWithOneRunningBackgroundSubagentStaysRunning() throws {
        let stop = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Stop",
              "background_tasks": [
                {"id": "bg-1", "type": "subagent", "status": "running", "description": "lint"}
              ]
            }
            """
        )

        #expect(stop?.kind == .running)
        #expect(stop?.message == "Waiting for 1 background agent")
    }

    @Test("pluralizes the wait message for multiple in-flight background subagents")
    func stopWithMultipleRunningBackgroundSubagentsPluralizesMessage() throws {
        let stop = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Stop",
              "background_tasks": [
                {"id": "bg-1", "type": "subagent", "status": "running"},
                {"id": "bg-2", "type": "subagent", "status": "running"}
              ]
            }
            """
        )

        #expect(stop?.kind == .running)
        #expect(stop?.message == "Waiting for 2 background agents")
    }

    @Test("keeps a run open while an in-flight workflow task is still running")
    func stopWithRunningWorkflowStaysRunning() throws {
        let stop = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Stop",
              "background_tasks": [
                {"id": "bg-1", "type": "workflow", "status": "running"}
              ]
            }
            """
        )

        #expect(stop?.kind == .running)
    }

    @Test(
        "treats Stop as complete when background_tasks has no in-flight subagent/workflow entry",
        arguments: [
            // A running shell task (dev server, `tail -f`) doesn't count --
            // it can outlive the agent's own work entirely.
            #"[{"id": "bg-1", "type": "shell", "status": "running"}]"#,
            // A subagent already reported finished doesn't count.
            #"[{"id": "bg-1", "type": "subagent", "status": "completed"}]"#,
            // No background_tasks at all.
            "[]",
            "null",
            // Malformed entries: a bare string, and one missing "type".
            #"["not-an-object"]"#,
            #"[{"id": "bg-1", "status": "running"}]"#,
        ]
    )
    func stopWithoutInFlightBackgroundAgentsSucceeds(backgroundTasksJSON: String) throws {
        let stop = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Stop",
              "background_tasks": \(backgroundTasksJSON)
            }
            """
        )

        #expect(stop?.kind == .succeeded)
    }

    @Test("Stop with no background_tasks field at all still succeeds")
    func stopWithMissingBackgroundTasksFieldSucceeds() throws {
        let stop = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Stop"
            }
            """
        )

        #expect(stop?.kind == .succeeded)
    }

    @Test("does not map idle_prompt notifications, but keeps agent_needs_input as input-requested")
    func idlePromptIsNotMappedButAgentNeedsInputIs() throws {
        let idlePrompt = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Notification",
              "notification_type": "idle_prompt"
            }
            """
        )
        let agentNeedsInput = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Notification",
              "notification_type": "agent_needs_input"
            }
            """
        )

        #expect(idlePrompt == nil)
        #expect(agentNeedsInput?.kind == .inputRequested)
    }

    @Test("a run left running by a background wait stays running until superseded")
    func backgroundWaitRunStaysRunningUntilSuperseded() throws {
        let userPromptSubmit = try #require(try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "UserPromptSubmit"
            }
            """
        ))
        let stop = try #require(try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "Stop",
              "background_tasks": [
                {"id": "bg-1", "type": "subagent", "status": "running"}
              ]
            }
            """
        ))

        let runningRuns = AgentEventReducer.reduce([userPromptSubmit, stop])
        #expect(runningRuns[userPromptSubmit.runID]?.state == .running)

        let newRun = try #require(makeRun(inState: .running))
        let supersede = AgentHookEventAdapter.supersededRunSweepEvent(
            run: try #require(runningRuns[userPromptSubmit.runID]),
            supersededBy: newRun.id,
            occurredAt: occurredAt.addingTimeInterval(120)
        )

        let sweptRuns = AgentEventReducer.reduce([userPromptSubmit, stop, supersede])
        #expect(sweptRuns[userPromptSubmit.runID]?.state == .idle)
    }

    @Test("captures the tool name on a Claude Code permission request")
    func claudeCodePermissionRequestCapturesToolName() throws {
        let approval = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "PermissionRequest",
              "tool_name": "Bash"
            }
            """
        )

        #expect(approval?.kind == .approvalRequested)
        #expect(approval?.toolName == "Bash")
    }

    @Test("has no tool name when the provider does not report one")
    func toolNameNilWhenAbsent() throws {
        let event = try event(
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

        #expect(event?.toolName == nil)
    }

    @Test("strips control characters and clamps an overlong tool name")
    func toolNameSanitizesControlCharactersAndLength() throws {
        let overlong = String(repeating: "a", count: 200)
        let withControlCharacters = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "PermissionRequest",
              "tool_name": "Ba\\nsh"
            }
            """
        )
        let clamped = try event(
            provider: .claudeCode,
            payload: """
            {
              "session_id": "claude-session",
              "prompt_id": "1d97fd10-721e-4d85-bf79-c63b502fa365",
              "hook_event_name": "PermissionRequest",
              "tool_name": "\(overlong)"
            }
            """
        )

        #expect(withControlCharacters?.toolName == "Bash")
        #expect(clamped?.toolName?.utf8.count == 128)
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
        #expect(preToolUse?.toolName == "Delete")
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
        #expect(pending.toolName == "Delete")

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

    // MARK: - Startup sweep

    @Test(
        "sweeps only non-terminal states, leaving unknown/idle/terminal runs alone",
        arguments: [
            (AgentRunState.unknown, false),
            (.idle, false),
            (.running, true),
            (.waitingInput, true),
            (.waitingApproval, true),
            (.succeeded, false),
            (.failed, false),
            (.disconnected, false),
        ]
    )
    func runsNeedingStartupSweepStateMatrix(
        state: AgentRunState,
        needsSweep: Bool
    ) throws {
        let run = try #require(makeRun(inState: state))

        let swept = AgentHookEventAdapter.runsNeedingStartupSweep([run])

        #expect(swept.map(\.id) == (needsSweep ? [run.id] : []))
    }

    @Test("startup sweep event is disconnected, carries the run's fields, and is deterministic per run")
    func startupSweepEventFieldsAndDeterminism() throws {
        let run = try #require(makeRun(inState: .waitingApproval))

        let first = AgentHookEventAdapter.startupSweepEvent(
            run: run,
            occurredAt: occurredAt
        )
        let second = AgentHookEventAdapter.startupSweepEvent(
            run: run,
            occurredAt: occurredAt.addingTimeInterval(3600)
        )

        #expect(first.kind == .disconnected)
        #expect(first.runID == run.id)
        #expect(first.surfaceID == run.surfaceID)
        #expect(first.provider == run.provider)
        #expect(first.sessionID == run.sessionID)
        #expect(first.hookName == "mytty.startupSweep")
        // Deterministic per run ID, not per call/occurredAt: a sweep of the
        // same run on a later launch must land on the exact same event so
        // replay dedup treats it as a no-op.
        #expect(first.id == second.id)
    }

    @Test("applying a startup sweep event closes a running run, and re-applying it is a no-op")
    func sweepEventClosesRunAndIsIdempotentOnReplay() throws {
        let runID = AgentRunID()
        let started = AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .claudeCode,
            kind: .started,
            occurredAt: occurredAt
        )
        let runningRuns = AgentEventReducer.reduce([started])
        let run = try #require(runningRuns[runID])
        #expect(run.state == .running)

        let sweep = AgentHookEventAdapter.startupSweepEvent(
            run: run,
            occurredAt: occurredAt.addingTimeInterval(60)
        )

        let sweptOnce = AgentEventReducer.reduce([started, sweep])
        #expect(sweptOnce[runID]?.state == .disconnected)
        let acceptedAfterOneSweep = sweptOnce[runID]?.acceptedEventCount

        // The same event ID appearing twice (e.g. a sweep recorded, then
        // the log replayed again on a later launch) must not be applied
        // twice.
        let sweptTwice = AgentEventReducer.reduce([started, sweep, sweep])
        #expect(sweptTwice[runID]?.state == .disconnected)
        #expect(sweptTwice[runID]?.acceptedEventCount == acceptedAfterOneSweep)
    }

    // MARK: - Superseded run sweep

    @Test("superseded run sweep event is idle, mytty-synthesized, and deterministic per (old run, new run) pair")
    func supersededRunSweepEventFieldsAndDeterminism() throws {
        let run = try #require(makeRun(inState: .running))
        let newRunID = AgentRunID()

        let first = AgentHookEventAdapter.supersededRunSweepEvent(
            run: run,
            supersededBy: newRunID,
            occurredAt: occurredAt
        )
        let second = AgentHookEventAdapter.supersededRunSweepEvent(
            run: run,
            supersededBy: newRunID,
            occurredAt: occurredAt.addingTimeInterval(3600)
        )

        #expect(first.kind == .idle)
        #expect(first.runID == run.id)
        #expect(first.surfaceID == run.surfaceID)
        #expect(first.provider == run.provider)
        #expect(first.sessionID == run.sessionID)
        #expect(AgentHookEventAdapter.isMyttySynthesizedHookName(first.hookName))
        // Deterministic per (old run, new run) pair, not per call/occurredAt
        // -- re-detecting the same supersession a second time must land on
        // the same event so replay dedup treats it as a no-op.
        #expect(first.id == second.id)
    }

    /// Builds an `AgentRun` sitting in `state` via the reducer -- `AgentRun`
    /// has no public initializer, so tests can only produce one by
    /// replaying events, the same way production code does.
    private func makeRun(inState state: AgentRunState) -> AgentRun? {
        let runID = AgentRunID()
        let kinds: [AgentEventKind] = switch state {
        case .unknown: [.succeeded] // invalid from .unknown: stays unknown
        case .idle: [.idle]
        case .running: [.started]
        case .waitingInput: [.started, .inputRequested]
        case .waitingApproval: [.started, .approvalRequested]
        case .succeeded: [.started, .succeeded]
        case .failed: [.started, .failed]
        case .disconnected: [.disconnected]
        }
        let events = kinds.enumerated().map { index, kind in
            AgentEvent(
                runID: runID,
                sessionID: "session-\(state.rawValue)",
                surfaceID: surfaceID,
                provider: .claudeCode,
                kind: kind,
                occurredAt: occurredAt.addingTimeInterval(TimeInterval(index))
            )
        }
        let run = AgentEventReducer.reduce(events)[runID]
        precondition(run?.state == state, "test setup produced the wrong state")
        return run
    }
}
