import Darwin
import Foundation

public struct AgentSessionStatus: Equatable, Sendable {
    public let sessionID: String?
    public let modelName: String?
    public let contextRemainingPercent: Double?

    public init(
        sessionID: String?,
        modelName: String?,
        contextRemainingPercent: Double?
    ) {
        self.sessionID = sessionID
        self.modelName = modelName
        self.contextRemainingPercent = contextRemainingPercent
    }
}

public enum AgentSessionIDSelection {
    public static func resolve(
        processBound: String?,
        hook: String?
    ) -> String? {
        processBound ?? hook
    }
}

/// What one read of the Codex rollout the process holds open yields.
public struct CodexTranscriptSnapshot: Equatable, Sendable {
    public let status: AgentSessionStatus?
    /// The current prompt-turn's lifecycle, derived from the same tail
    /// (see `CodexSessionInspector.turn(from:)`) -- feeds
    /// `NativeAgentRunEstimator.turnObserved` for panes whose hook
    /// integration isn't installed. `nil` when the tail carries no
    /// `task_started` at all.
    public let turn: AgentTurnObservation?

    public init(status: AgentSessionStatus?, turn: AgentTurnObservation?) {
        self.status = status
        self.turn = turn
    }
}

public enum CodexSessionInspector {
    private static let maximumMetadataBytes = 1_024 * 1_024
    private static let maximumStatusTailBytes = 512 * 1_024

    public static func sessionID(
        processID: pid_t,
        codexHome: URL = defaultCodexHome
    ) -> String? {
        guard processID > 0 else { return nil }
        return openSessionTranscripts(
            processID: processID,
            codexHome: codexHome
        )
        .sorted { modificationDate($0) > modificationDate($1) }
        .lazy
        .compactMap(readMetadata)
        .first
    }

    public static func status(
        processID: pid_t,
        codexHome: URL = defaultCodexHome
    ) -> AgentSessionStatus? {
        snapshot(processID: processID, codexHome: codexHome).status
    }

    /// Combines the status read with a turn-lifecycle read over the exact
    /// same transcript tail, so a caller that needs both (`CodexProvider
    /// Runtime.poll`, unthrottled and called every 0.5s) doesn't pay for
    /// the process fd scan (`openSessionTranscripts`) twice.
    public static func snapshot(
        processID: pid_t,
        codexHome: URL = defaultCodexHome
    ) -> CodexTranscriptSnapshot {
        guard processID > 0 else {
            return CodexTranscriptSnapshot(status: nil, turn: nil)
        }
        return openSessionTranscripts(
            processID: processID,
            codexHome: codexHome
        )
        .sorted { modificationDate($0) > modificationDate($1) }
        .lazy
        .compactMap(readSnapshot)
        .first ?? CodexTranscriptSnapshot(status: nil, turn: nil)
    }

    /// Reads the tail of the transcript the Codex process holds open and
    /// returns the user's most recent prompts, oldest first — material for
    /// inferring what the user is trying to accomplish (e.g. when naming
    /// the tab).
    public static func recentUserPrompts(
        processID: pid_t,
        codexHome: URL = defaultCodexHome,
        limit: Int
    ) -> [String] {
        guard processID > 0 else { return [] }
        return openSessionTranscripts(
            processID: processID,
            codexHome: codexHome
        )
        .sorted { modificationDate($0) > modificationDate($1) }
        .lazy
        .map { url -> [String] in
            guard let data = readTailData(from: url) else { return [] }
            return recentUserPrompts(from: data, limit: limit)
        }
        .first { !$0.isEmpty } ?? []
    }

    static func recentUserPrompts(from data: Data, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var eventPrompts: [String] = []
        var responsePrompts: [String] = []

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line)
            ) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { continue }

            switch type {
            case "event_msg":
                guard payload["type"] as? String == "user_message",
                      isPlainKind(payload["kind"]),
                      let message = payload["message"] as? String,
                      !isInjectedText(message),
                      let prompt = AgentSessionValidation.promptText(message)
                else { continue }
                eventPrompts.append(prompt)
            case "response_item":
                // Older rollouts carry no user_message events; the raw
                // conversation items are the fallback prompt source.
                guard payload["type"] as? String == "message",
                      payload["role"] as? String == "user",
                      let blocks = payload["content"] as? [[String: Any]]
                else { continue }
                let texts = blocks.compactMap { block -> String? in
                    guard block["type"] as? String == "input_text" else {
                        return nil
                    }
                    return block["text"] as? String
                }
                .filter { !isInjectedText($0) }
                guard !texts.isEmpty,
                      let prompt = AgentSessionValidation.promptText(
                          texts.joined(separator: " ")
                      )
                else { continue }
                responsePrompts.append(prompt)
            default:
                continue
            }
        }

        let prompts = eventPrompts.isEmpty ? responsePrompts : eventPrompts
        return Array(prompts.suffix(limit))
    }

    /// Codex marks injected user messages with a `kind`; anything other
    /// than a plain prompt (user instructions, environment context) is not
    /// something the user typed.
    private static func isPlainKind(_ kind: Any?) -> Bool {
        guard let kind = kind as? String else { return kind == nil }
        return kind == "plain"
    }

    private static let injectedTextPrefixes = [
        "<user_instructions>",
        "<environment_context>",
        "<ENVIRONMENT_CONTEXT>",
        "<turn_aborted>",
    ]

    private static func isInjectedText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return injectedTextPrefixes.contains { trimmed.hasPrefix($0) }
    }

    static func sessionID(from data: Data) -> String? {
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = data.prefix(upTo: newline)
        } else {
            line = data
        }
        guard let object = try? JSONSerialization.jsonObject(with: line)
            as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        return AgentSessionValidation.identifier(
            payload["session_id"] as? String
                ?? payload["id"] as? String
        )
    }

    static func status(from data: Data) -> AgentSessionStatus? {
        var sessionID: String?
        var modelName: String?
        var contextRemainingPercent: Double?

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line)
            ) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { continue }

            switch type {
            case "session_meta":
                sessionID = AgentSessionValidation.identifier(
                    payload["session_id"] as? String
                        ?? payload["id"] as? String
                ) ?? sessionID
            case "turn_context":
                modelName = AgentSessionValidation.label(
                    payload["model"] as? String
                ) ?? modelName
            case "event_msg":
                guard payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let window = positiveDouble(
                          info["model_context_window"]
                      ),
                      let usage = (info["last_token_usage"]
                          ?? info["total_token_usage"])
                          as? [String: Any],
                      let tokens = tokenCount(from: usage)
                else { continue }
                contextRemainingPercent = min(
                    100,
                    max(0, (1 - tokens / window) * 100)
                )
            default:
                continue
            }
        }

        guard sessionID != nil || modelName != nil
                || contextRemainingPercent != nil
        else { return nil }
        return AgentSessionStatus(
            sessionID: sessionID,
            modelName: modelName,
            contextRemainingPercent: contextRemainingPercent
        )
    }

    /// Reduces the rollout tail to the current turn's lifecycle, mirroring
    /// the `UserPromptSubmit`-to-`Stop` cycle a real hook integration
    /// reports: `task_started` begins a turn, keyed by its `turn_id` --
    /// the same identifier Codex's own hooks report as `turn_id` on their
    /// payloads, so a turn key always lines up with a hook-derived run.
    /// `task_complete` completes it; `turn_aborted` (the user interrupting,
    /// or the CLI itself giving up) marks it interrupted. Turns are strictly
    /// sequential in a rollout -- one active at a time -- so this only
    /// needs to track the latest `task_started` and whatever followed it,
    /// the same ordinal approach `ClaudeCodeSessionInspector.turn(from:)`
    /// uses. `nil` when the tail carries no `task_started` at all.
    static func turn(from data: Data) -> AgentTurnObservation? {
        var turnKey: String?
        var phase: AgentTurnObservation.Phase = .active

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line)
            ) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let kind = payload["type"] as? String
            else { continue }

            switch kind {
            case "task_started":
                guard let key = codexTurnKey(
                    payload: payload,
                    record: object
                ) else { continue }
                turnKey = key
                phase = .active
            case "task_complete":
                guard turnKey != nil else { continue }
                phase = .completed
            case "turn_aborted":
                guard turnKey != nil else { continue }
                phase = .interrupted
            default:
                continue
            }
        }

        guard let turnKey else { return nil }
        return AgentTurnObservation(key: turnKey, phase: phase)
    }

    /// `turn_id` is present on every real `task_started` payload observed
    /// in practice; the record's own `timestamp` is a stable-enough
    /// fallback for a malformed or unusually old rollout that lacks it --
    /// it just needs to be stable across repeated reads of the same file
    /// and distinct across turns, which a millisecond-precision timestamp
    /// string satisfies.
    private static func codexTurnKey(
        payload: [String: Any],
        record: [String: Any]
    ) -> String? {
        AgentSessionValidation.identifier(payload["turn_id"] as? String)
            ?? AgentSessionValidation.identifier(
                record["timestamp"] as? String
            )
    }

    public static var defaultCodexHome: URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func openSessionTranscripts(
        processID: pid_t,
        codexHome: URL
    ) -> [URL] {
        let descriptorSize = MemoryLayout<proc_fdinfo>.stride
        let requiredBytes = proc_pidinfo(
            processID,
            PROC_PIDLISTFDS,
            0,
            nil,
            0
        )
        guard requiredBytes > 0 else { return [] }

        let capacity = Int(requiredBytes) / descriptorSize + 16
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: capacity
        )
        let actualBytes = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(
                processID,
                PROC_PIDLISTFDS,
                0,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard actualBytes > 0 else { return [] }

        let sessionsDirectory = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let sessionsPrefix = sessionsDirectory.hasSuffix("/")
            ? sessionsDirectory
            : sessionsDirectory + "/"
        return descriptors
            .prefix(Int(actualBytes) / descriptorSize)
            .compactMap { descriptor in
                guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE,
                      let path = vnodePath(
                        processID: processID,
                        fileDescriptor: descriptor.proc_fd
                      ),
                      path.hasSuffix(".jsonl")
                else { return nil }
                let url = URL(fileURLWithPath: path, isDirectory: false)
                    .resolvingSymlinksInPath().standardizedFileURL
                guard url.path.hasPrefix(sessionsPrefix) else { return nil }
                return url
            }
    }

    private static func vnodePath(
        processID: pid_t,
        fileDescriptor: Int32
    ) -> String? {
        var info = vnode_fdinfowithpath()
        let expectedSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidfdinfo(
                processID,
                fileDescriptor,
                PROC_PIDFDVNODEPATHINFO,
                pointer,
                expectedSize
            )
        }
        guard result >= expectedSize else { return nil }
        return withUnsafePointer(to: &info.pvip.vip_path) { path in
            path.withMemoryRebound(
                to: CChar.self,
                capacity: Int(MAXPATHLEN)
            ) {
                let value = String(cString: $0)
                return value.isEmpty ? nil : value
            }
        }
    }

    private static func readMetadata(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(
            upToCount: maximumMetadataBytes
        ) else { return nil }
        return sessionID(from: data)
    }

    private static func readTailData(from url: URL) -> Data? {
        FileTailReader.tail(of: url, maximumBytes: maximumStatusTailBytes)
    }

    /// `session_meta`/`turn_context` (the status fields) are written once,
    /// near the start of the rollout, so a large file's tail alone can miss
    /// them -- this falls back to reading the file's head and combining it
    /// with the tail, exactly as the pre-turn-tracking `readStatus` did.
    /// The turn fields (`task_started`/`task_complete`/`turn_aborted`) are
    /// activity that happens throughout the session, so the tail alone
    /// (`data`, read once here) is always sufficient for them -- no second
    /// fd read needed to add turn support.
    private static func readSnapshot(from url: URL) -> CodexTranscriptSnapshot? {
        guard let data = readTailData(from: url) else { return nil }
        let turnObservation = turn(from: data)

        if let status = status(from: data), status.sessionID != nil {
            return CodexTranscriptSnapshot(status: status, turn: turnObservation)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return CodexTranscriptSnapshot(
                status: status(from: data),
                turn: turnObservation
            )
        }
        defer { try? handle.close() }
        guard let metadata = try? handle.read(
            upToCount: maximumMetadataBytes
        ) else {
            return CodexTranscriptSnapshot(
                status: status(from: data),
                turn: turnObservation
            )
        }
        var combined = metadata
        combined.append(0x0A)
        combined.append(data)
        return CodexTranscriptSnapshot(
            status: status(from: combined),
            turn: turnObservation
        )
    }

    private static func modificationDate(_ url: URL) -> Date {
        FileFingerprint.modificationDate(of: url)
    }

    private static func tokenCount(from usage: [String: Any]) -> Double? {
        if let total = positiveDouble(usage["total_tokens"]) {
            return total
        }
        let input = nonnegativeDouble(usage["input_tokens"])
        let output = nonnegativeDouble(usage["output_tokens"])
        guard input != nil || output != nil else { return nil }
        return (input ?? 0) + (output ?? 0)
    }

    private static func positiveDouble(_ value: Any?) -> Double? {
        guard let value = nonnegativeDouble(value), value > 0 else {
            return nil
        }
        return value
    }

    private static func nonnegativeDouble(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite, number >= 0 else { return nil }
        return number
    }
}
