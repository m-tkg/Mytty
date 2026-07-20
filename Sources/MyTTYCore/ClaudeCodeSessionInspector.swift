import Foundation

/// A prompt the user interrupted with ESC. `messageID` identifies the
/// interrupt itself: one prompt can be interrupted, continued, and
/// interrupted again, and each of those must end the run separately.
public struct ClaudeCodeInterruption: Equatable, Sendable {
    public let promptID: String
    public let messageID: String

    public init(promptID: String, messageID: String) {
        self.promptID = promptID
        self.messageID = messageID
    }
}

/// What one read of a Claude Code transcript tail yields.
public struct ClaudeCodeTranscriptSnapshot: Equatable, Sendable {
    public let status: AgentSessionStatus?
    /// Set while the newest prompt ended in a user interrupt (ESC).
    public let interruption: ClaudeCodeInterruption?

    public init(
        status: AgentSessionStatus?,
        interruption: ClaudeCodeInterruption?
    ) {
        self.status = status
        self.interruption = interruption
    }
}

public enum ClaudeCodeSessionInspector {
    private static let maximumStatusTailBytes = 512 * 1_024
    private static let largeContextWindow: Double = 1_000_000
    private static let defaultContextWindow: Double = 200_000

    /// Best-known context window for a model label. The 200k default made
    /// Mythos-class sessions (claude-fable-5 etc.) pin the meter at 0% as
    /// soon as their usage passed 200k; their exact window isn't published
    /// in the transcript, so they share the 1M large-window estimate.
    static func contextWindow(forModel model: String?) -> Double {
        guard let model = model?.lowercased() else {
            return defaultContextWindow
        }
        if model.contains("[1m]")
            || model.contains("fable")
            || model.contains("mythos") {
            return largeContextWindow
        }
        return defaultContextWindow
    }

    static func status(
        sessionID: String?,
        workingDirectory: URL?,
        claudeHome: URL = defaultClaudeHome
    ) -> AgentSessionStatus? {
        guard let transcript = transcriptURL(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            claudeHome: claudeHome
        ) else { return nil }
        return status(contentsOf: transcript)
    }

    /// Locates the transcript for a session without reading it, so callers
    /// can cheaply fingerprint the file (mtime/size) before deciding whether
    /// a re-parse is needed.
    public static func transcriptURL(
        sessionID: String?,
        workingDirectory: URL?,
        claudeHome: URL = defaultClaudeHome
    ) -> URL? {
        let projectsDirectory = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
        if let sessionID = AgentSessionValidation.identifier(sessionID),
           let transcript = findTranscript(
               bySessionID: sessionID,
               projectsDirectory: projectsDirectory
           ) {
            return transcript
        }
        // The hook can report a session ID before Claude Code writes its
        // transcript (no prompt submitted yet), so fall back to the newest
        // transcript of the surface's working directory.
        guard let workingDirectory else { return nil }
        let projectDirectory = projectsDirectory.appendingPathComponent(
            slug(for: workingDirectory),
            isDirectory: true
        )
        return newestTranscript(in: projectDirectory)
    }

    public static func status(contentsOf url: URL) -> AgentSessionStatus? {
        snapshot(contentsOf: url).status
    }

    /// One pass over the transcript tail for everything the poller needs:
    /// the session status *and* whether the newest prompt ended in a user
    /// interrupt. Claude Code fires no hook when the user presses ESC, so
    /// the interrupted prompt is the only record that a run stopped.
    public static func snapshot(
        contentsOf url: URL
    ) -> ClaudeCodeTranscriptSnapshot {
        guard let data = readTail(from: url) else {
            return ClaudeCodeTranscriptSnapshot(
                status: nil,
                interruption: nil
            )
        }
        return ClaudeCodeTranscriptSnapshot(
            status: status(from: data).map { parsed in
                guard parsed.sessionID == nil else { return parsed }
                // A transcript is named after its session, so fall back to
                // the file name when no line carried a session ID.
                let stem = url.deletingPathExtension().lastPathComponent
                return AgentSessionStatus(
                    sessionID: AgentSessionValidation.identifier(stem),
                    modelName: parsed.modelName,
                    contextRemainingPercent: parsed.contextRemainingPercent
                )
            },
            interruption: interruption(from: data)
        )
    }

    /// The newest prompt if — and only if — the last transcript entry
    /// belonging to it is Claude Code's interrupt marker
    /// (`interruptedMessageId`). Any later entry — the next prompt, or more
    /// input continuing this one — means the run is live again, so nothing
    /// is reported.
    static func interruption(from data: Data) -> ClaudeCodeInterruption? {
        var interruption: ClaudeCodeInterruption?

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line)
            ) as? [String: Any],
                  (object["isSidechain"] as? Bool) != true,
                  let promptID = AgentSessionValidation.identifier(
                      object["promptId"] as? String
                  )
            else { continue }

            let messageID = object["type"] as? String == "user"
                ? AgentSessionValidation.identifier(
                    object["interruptedMessageId"] as? String
                )
                : nil
            interruption = messageID.map {
                ClaudeCodeInterruption(promptID: promptID, messageID: $0)
            }
        }

        return interruption
    }

    static func status(from data: Data) -> AgentSessionStatus? {
        var sessionID: String?
        var modelName: String?
        var contextRemainingPercent: Double?

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(
                with: Data(line)
            ) as? [String: Any],
                  object["type"] as? String == "assistant",
                  (object["isSidechain"] as? Bool) != true,
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let tokens = tokenCount(from: usage)
            else { continue }

            let model = AgentSessionValidation.label(
                message["model"] as? String
            )
            let window = contextWindow(forModel: model)
            modelName = model ?? modelName
            contextRemainingPercent = min(
                100,
                max(0, (1 - tokens / window) * 100)
            )
            sessionID = AgentSessionValidation.identifier(
                object["sessionId"] as? String
            ) ?? sessionID
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

    /// Converts a working directory into the slug Claude Code uses for its
    /// per-project transcript directory (`~/.claude/projects/<slug>/`):
    /// every character that is not a letter or digit becomes `-`.
    static func slug(for directory: URL) -> String {
        String(
            directory.standardizedFileURL.path.unicodeScalars.map {
                scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar)
                    ? Character(scalar)
                    : "-"
            }
        )
    }

    public static var defaultClaudeHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    private static func findTranscript(
        bySessionID sessionID: String,
        projectsDirectory: URL
    ) -> URL? {
        guard let projectDirectories = try? FileManager.default
            .contentsOfDirectory(
                at: projectsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return nil }

        for projectDirectory in projectDirectories {
            let candidate = projectDirectory
                .appendingPathComponent("\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func newestTranscript(in directory: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private static func readTail(from url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let tailSize = min(UInt64(maximumStatusTailBytes), end)
        guard (try? handle.seek(toOffset: end - tailSize)) != nil else {
            return nil
        }
        return try? handle.readToEnd()
    }

    private static func modificationDate(_ url: URL) -> Date {
        FileFingerprint.modificationDate(of: url)
    }

    private static func tokenCount(from usage: [String: Any]) -> Double? {
        let input = nonnegativeDouble(usage["input_tokens"])
        let cacheRead = nonnegativeDouble(usage["cache_read_input_tokens"])
        let cacheCreation = nonnegativeDouble(
            usage["cache_creation_input_tokens"]
        )
        guard input != nil || cacheRead != nil || cacheCreation != nil
        else { return nil }
        return (input ?? 0) + (cacheRead ?? 0) + (cacheCreation ?? 0)
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
