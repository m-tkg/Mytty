import CryptoKit
import Foundation

public enum AgentHookEventAdapterError: Error, Equatable, Sendable {
    case invalidPayload
    case missingRunIdentifier
}

public enum AgentHookEventAdapter {
    public static func makeEvent(
        provider: AgentProvider,
        payload: Data,
        surfaceID: TerminalSurfaceID,
        occurredAt: Date
    ) throws -> AgentEvent? {
        guard let object = try JSONSerialization.jsonObject(
            with: payload
        ) as? [String: Any] else {
            throw AgentHookEventAdapterError.invalidPayload
        }

        let mapping: Mapping?
        switch provider {
        case .codex:
            mapping = codexMapping(object)
        case .claudeCode:
            mapping = claudeCodeMapping(object)
        case .openCode:
            mapping = openCodeMapping(object)
        case .antigravity:
            mapping = antigravityMapping(object)
        case .cursor:
            mapping = cursorMapping(object)
        }
        guard let mapping else { return nil }
        guard let runKey = mapping.runKey, !runKey.isEmpty else {
            throw AgentHookEventAdapterError.missingRunIdentifier
        }

        let canonicalPayload = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let runID = StableAgentUUID.make(
            from: "run\u{0}\(provider.rawValue)\u{0}\(runKey)"
        )
        var eventIdentity = Data(
            "event\u{0}\(provider.rawValue)\u{0}\(mapping.kind.rawValue)\u{0}".utf8
        )
        eventIdentity.append(canonicalPayload)

        return AgentEvent(
            id: AgentEventID(
                rawValue: StableAgentUUID.make(from: eventIdentity)
            ),
            runID: AgentRunID(rawValue: runID),
            sessionID: mapping.sessionID,
            surfaceID: surfaceID,
            provider: provider,
            kind: mapping.kind,
            occurredAt: occurredAt,
            message: mapping.message,
            hookName: mapping.hookName
        )
    }

    /// Builds the `idle` event that ends a run the provider never reported
    /// finishing — a prompt the user interrupted. `runKey` is the same value
    /// the provider's hooks use (Claude Code: the prompt ID), so the event
    /// lands on the existing run. `interruptionKey` identifies the interrupt
    /// itself, so re-detecting one is a no-op while a second interrupt of
    /// the same run still ends it.
    public static func interruptionEvent(
        provider: AgentProvider,
        runKey: String,
        interruptionKey: String,
        sessionID: String?,
        surfaceID: TerminalSurfaceID,
        occurredAt: Date
    ) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(
                rawValue: StableAgentUUID.make(
                    from: "event\u{0}\(provider.rawValue)\u{0}interrupted\u{0}\(runKey)\u{0}\(interruptionKey)"
                )
            ),
            runID: AgentRunID(
                rawValue: StableAgentUUID.make(
                    from: "run\u{0}\(provider.rawValue)\u{0}\(runKey)"
                )
            ),
            sessionID: sessionID,
            surfaceID: surfaceID,
            provider: provider,
            kind: .idle,
            occurredAt: occurredAt
        )
    }

    /// Builds the synthetic `approval-requested` event for Cursor, whose
    /// hooks never report a shell command waiting on user permission (see
    /// `CursorApprovalPendingTracker`). `runID` is reused as-is from the
    /// `beforeShellExecution` event that started the wait, so the
    /// synthetic event lands on that same run; the event ID is derived
    /// from `runID` + `command` so re-detecting the same stuck command is
    /// a no-op.
    public static func pendingApprovalEvent(
        runID: AgentRunID,
        command: String,
        sessionID: String?,
        surfaceID: TerminalSurfaceID,
        occurredAt: Date
    ) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(
                rawValue: StableAgentUUID.make(
                    from: "event\u{0}cursor\u{0}pending-approval\u{0}\(runID.rawValue.uuidString)\u{0}\(command)"
                )
            ),
            runID: runID,
            sessionID: sessionID,
            surfaceID: surfaceID,
            provider: .cursor,
            kind: .approvalRequested,
            occurredAt: occurredAt,
            message: command,
            hookName: syntheticPendingApprovalHookName
        )
    }

    /// Marks an event as mytty-synthesized rather than a real hook
    /// delivery, so `CursorApprovalPendingTracker` (fed every observed
    /// event, including ones it produced) never re-registers on its own
    /// output.
    static let syntheticPendingApprovalHookName = "mytty.cursorApprovalPending"

    private static func codexMapping(
        _ object: [String: Any]
    ) -> Mapping? {
        guard let eventName = object.string("hook_event_name") else {
            return nil
        }
        let kind: AgentEventKind
        switch eventName {
        case "SessionStart":
            kind = .idle
        case "UserPromptSubmit":
            kind = .started
        case "SessionEnd":
            kind = .disconnected
        case "PermissionRequest":
            kind = isInputTool(object.string("tool_name"))
                ? .inputRequested
                : .approvalRequested
        case "PostToolUse":
            kind = .running
        case "Stop":
            kind = .succeeded
        default:
            return nil
        }

        return Mapping(
            runKey: object.string("turn_id") ?? object.string("session_id"),
            sessionID: sessionIdentifier(object.string("session_id")),
            kind: kind,
            message: message(
                for: kind,
                toolName: object.string("tool_name"),
                directMessage: object.string("message")
            ),
            hookName: eventName
        )
    }

    private static func claudeCodeMapping(
        _ object: [String: Any]
    ) -> Mapping? {
        guard let eventName = object.string("hook_event_name") else {
            return nil
        }

        let kind: AgentEventKind
        switch eventName {
        case "SessionStart":
            kind = .idle
        case "UserPromptSubmit":
            kind = .started
        case "SessionEnd":
            kind = .disconnected
        case "PermissionRequest":
            kind = isInputTool(object.string("tool_name"))
                ? .inputRequested
                : .approvalRequested
        case "PostToolBatch":
            kind = .running
        case "Notification":
            switch object.string("notification_type") {
            case "permission_prompt":
                kind = .approvalRequested
            case "idle_prompt", "agent_needs_input", "elicitation_dialog":
                kind = .inputRequested
            case "agent_completed":
                kind = .succeeded
            default:
                return nil
            }
        case "Stop":
            kind = .succeeded
        case "StopFailure":
            kind = .failed
        default:
            return nil
        }

        return Mapping(
            runKey: object.string("prompt_id") ?? object.string("session_id"),
            sessionID: sessionIdentifier(object.string("session_id")),
            kind: kind,
            message: message(
                for: kind,
                toolName: object.string("tool_name"),
                directMessage: object.string("message")
                    ?? object.string("error_message")
            ),
            hookName: eventName
        )
    }

    private static func openCodeMapping(
        _ object: [String: Any]
    ) -> Mapping? {
        guard let event = object.object("event"),
              let eventType = event.string("type"),
              let properties = event.object("properties")
        else { return nil }
        let info = properties.object("info")

        let kind: AgentEventKind
        var directMessage: String?
        switch eventType {
        case "message.updated":
            guard properties.object("info")?.string("role") == "user" else {
                return nil
            }
            kind = .started
        case "permission.asked", "permission.updated":
            kind = .approvalRequested
            directMessage = properties.string("title")
        case "permission.replied":
            kind = .running
        case "question.asked":
            kind = .inputRequested
            directMessage = properties.string("title")
                ?? properties.array("questions")?.first?.string("header")
        case "session.idle":
            kind = .succeeded
        case "session.error":
            kind = .failed
            directMessage = properties.object("error")?
                .object("data")?
                .string("message")
                ?? properties.object("error")?.string("message")
        default:
            return nil
        }

        return Mapping(
            runKey: object.string("run_id"),
            sessionID: sessionIdentifier(
                properties.string("sessionID") ?? info?.string("sessionID")
            ),
            kind: kind,
            message: directMessage,
            hookName: eventType
        )
    }

    private static func antigravityMapping(
        _ object: [String: Any]
    ) -> Mapping? {
        let kind: AgentEventKind
        var directMessage: String?
        let hookName: String?

        if object["fullyIdle"] != nil {
            let error = object.string("error")
            let terminationReason = object.string("terminationReason")
            if terminationReason == "error"
                || terminationReason == "max_steps_exceeded"
                || error?.isEmpty == false {
                kind = .failed
                directMessage = error
            } else {
                kind = .succeeded
            }
            hookName = "Stop"
        } else if object["invocationNum"] != nil {
            kind = .running
            // PreInvocation and PostInvocation post the same shape, so the
            // payload alone can't tell them apart.
            hookName = nil
        } else {
            return nil
        }

        return Mapping(
            runKey: object.string("conversationId"),
            sessionID: sessionIdentifier(object.string("conversationId")),
            kind: kind,
            message: directMessage,
            hookName: hookName
        )
    }

    private static func cursorMapping(
        _ object: [String: Any]
    ) -> Mapping? {
        guard let eventName = object.string("hook_event_name") else {
            return nil
        }

        let kind: AgentEventKind
        var directMessage: String?
        switch eventName {
        case "beforeSubmitPrompt":
            kind = .started
        case "postToolUse", "postToolUseFailure":
            kind = .running
        case "beforeShellExecution", "afterShellExecution":
            // Cursor has no dedicated approval-prompt hook, so these two
            // just report progress; CursorApprovalPendingTracker watches
            // the gap between them to estimate a stuck approval.
            kind = .running
            directMessage = object.string("command")
        case "stop":
            switch object.string("status") {
            case "completed":
                kind = .succeeded
            case "error":
                kind = .failed
                directMessage = object.string("error")
            case "aborted":
                kind = .disconnected
            default:
                // A `stop` with a missing or unrecognized `status` still
                // means the turn ended, so treat it as a normal
                // completion rather than dropping the event: a run that
                // finished this way would never clear from Attention.
                kind = .succeeded
            }
        default:
            return nil
        }

        let sessionID = sessionIdentifier(
            object.string("conversation_id") ?? object.string("session_id")
        )
        return Mapping(
            runKey: object.string("generation_id")
                ?? sessionID,
            sessionID: sessionID,
            kind: kind,
            message: directMessage,
            hookName: eventName
        )
    }

    private static func isInputTool(_ toolName: String?) -> Bool {
        switch toolName {
        case "AskUserQuestion", "request_user_input", "question":
            true
        default:
            false
        }
    }

    private static func message(
        for kind: AgentEventKind,
        toolName: String?,
        directMessage: String?
    ) -> String? {
        if let directMessage, !directMessage.isEmpty {
            return directMessage
        }
        guard kind == .approvalRequested, let toolName, !toolName.isEmpty else {
            return nil
        }
        return "\(toolName) requires approval"
    }

    private static func sessionIdentifier(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= 256,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }
        return value
    }
}

private struct Mapping {
    let runKey: String?
    let sessionID: String?
    let kind: AgentEventKind
    let message: String?
    let hookName: String?
}

private enum StableAgentUUID {
    static func make(from string: String) -> UUID {
        make(from: Data(string.utf8))
    }

    static func make(from data: Data) -> UUID {
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func object(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func array(_ key: String) -> [[String: Any]]? {
        self[key] as? [[String: Any]]
    }
}
