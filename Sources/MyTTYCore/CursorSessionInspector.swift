import Foundation
import SQLite3

/// What one read of a Cursor conversation's `store.db` yields. Mirrors
/// `ClaudeCodeTranscriptSnapshot`/`CodexTranscriptSnapshot`'s shape so the
/// three transcript-backed providers expose their poll-tick data the same
/// way, even though Cursor's source is a SQLite database rather than a
/// line-oriented transcript.
public struct CursorConversationSnapshot: Equatable, Sendable {
    public let status: AgentSessionStatus?
    /// The current prompt-turn's lifecycle, derived from the same `blobs`
    /// scan (see `CursorSessionInspector.turn(from:conversationID:)`) --
    /// feeds `NativeAgentRunEstimator.turnObserved` for panes whose hook
    /// integration isn't installed. `nil` when the scanned tail carries no
    /// real user prompt at all. Cursor writes no marker for an interrupted
    /// turn, so this phase is never `.interrupted` -- process exit already
    /// covers that case for a native-estimated run.
    public let turn: AgentTurnObservation?
    /// The conversation's `mode` (`plan`/`ask`), read from `meta` in the
    /// same connection. `nil` when `meta` carries no recognized mode.
    public let mode: String?

    public init(
        status: AgentSessionStatus?,
        turn: AgentTurnObservation?,
        mode: String?
    ) {
        self.status = status
        self.turn = turn
        self.mode = mode
    }
}

/// Reads the model name and context-window usage Cursor most recently
/// recorded for a chat conversation. The model name comes from a message
/// blob's `providerOptions.cursor.modelName` field; the context budget
/// comes from the newest "root" blob, which carries a small protobuf
/// record (used tokens / context window total) alongside the
/// conversation's metadata. Older Cursor CLI versions never write that
/// root blob, so `contextRemainingPercent` is `nil` in that case.
public enum CursorSessionInspector {
    public static func status(
        sessionID: String?,
        workingDirectory: URL?,
        cursorHome: URL = defaultCursorHome
    ) -> AgentSessionStatus? {
        snapshot(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            cursorHome: cursorHome
        ).status
    }

    /// One database read for everything a poll tick needs: the session
    /// status, the current prompt-turn's lifecycle, and the conversation's
    /// `mode` -- see `CursorConversationSnapshot`.
    public static func snapshot(
        sessionID: String?,
        workingDirectory: URL?,
        cursorHome: URL = defaultCursorHome
    ) -> CursorConversationSnapshot {
        let chatsDirectory = cursorHome
            .appendingPathComponent("chats", isDirectory: true)
        guard let conversationDirectory = conversationDirectory(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            chatsDirectory: chatsDirectory
        ) else {
            return CursorConversationSnapshot(status: nil, turn: nil, mode: nil)
        }

        let resolvedSessionID = AgentSessionValidation.identifier(sessionID)
            ?? AgentSessionValidation.identifier(
                conversationDirectory.lastPathComponent
            )
        let details = latestConversationDetails(
            storeDatabaseURL: conversationDirectory
                .appendingPathComponent("store.db"),
            conversationID: resolvedSessionID
        )

        let status = details.modelName.map { modelName in
            AgentSessionStatus(
                sessionID: resolvedSessionID,
                modelName: modelName,
                contextRemainingPercent: details.contextUsage.map { usage in
                    // Match Claude Code's convention: round the *used*
                    // share to a whole percent and subtract it, rather
                    // than rounding the remainder (see
                    // ClaudeCodeSessionInspector.status(from:)).
                    100 - min(
                        100,
                        max(0, (usage.used / usage.total * 100).rounded())
                    )
                }
            )
        }

        return CursorConversationSnapshot(
            status: status,
            turn: details.turn,
            mode: details.mode
        )
    }

    public static var defaultCursorHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
    }

    /// Extracts the `providerOptions.cursor.modelName` value from a raw
    /// message blob. Blobs sometimes carry a binary prefix ahead of the
    /// JSON payload, so this scans the lossily-decoded text for the field
    /// rather than requiring the whole blob to be valid JSON.
    static func extractModelName(from data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let markerRange = text.range(of: "\"modelName\":\"")
        else { return nil }
        let remainder = text[markerRange.upperBound...]
        guard let endQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }
        return AgentSessionValidation.label(String(remainder[..<endQuote]))
    }

    /// The `--mode` values `cursor-agent --help` documents (`--mode
    /// <mode>`, choices `plan`/`ask`; `--plan` is a shorthand for `--mode
    /// plan`). A `meta.mode` value outside this set -- including a future
    /// mode name -- is treated as unknown rather than surfaced, mirroring
    /// `ClaudeCodeSessionInspector`'s `knownPermissionModes` gate.
    static let knownModes: Set<String> = ["plan", "ask"]

    /// Extracts the `mode` value from a conversation's `meta` row.
    /// Mirrors `extractModelName`'s tolerance: some databases carry a
    /// binary prefix ahead of the JSON payload, so this scans the
    /// lossily-decoded text for the field marker rather than requiring the
    /// whole value to be valid JSON.
    static func extractMode(from data: Data) -> String? {
        let text = String(
            decoding: hexDecoded(data) ?? data,
            as: UTF8.self
        )
        guard let markerRange = text.range(of: "\"mode\":\"")
        else { return nil }
        let remainder = text[markerRange.upperBound...]
        guard let endQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }
        guard let label = AgentSessionValidation.label(
            String(remainder[..<endQuote])
        ) else { return nil }
        return knownModes.contains(label) ? label : nil
    }

    /// Cursor stores the `meta` row's JSON as its hex transcription
    /// (`7b22...` for `{"`) rather than as the JSON text itself, so the
    /// payload has to be decoded before any field can be read. Returns
    /// `nil` for anything that isn't an even-length run of hex digits,
    /// which is how a database that stores the JSON directly (or a value
    /// carrying a binary prefix) falls back to being scanned as-is.
    private static func hexDecoded(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count % 2 == 0 else { return nil }
        var decoded = Data(capacity: data.count / 2)
        var high: UInt8?
        for byte in data {
            let nibble: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                nibble = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                nibble = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                nibble = byte - UInt8(ascii: "A") + 10
            default:
                return nil
            }
            if let first = high {
                decoded.append(first << 4 | nibble)
                high = nil
            } else {
                high = nibble
            }
        }
        return decoded
    }

    /// Parses a message blob's JSON, tolerating a binary prefix ahead of
    /// the payload the same way `extractModelName` does: a real message
    /// blob's payload starts at the first `{"` (the outer brace followed
    /// immediately by a quoted key). Unlike the single-field scans above,
    /// turn detection needs the whole `content` array structurally (which
    /// of its elements are `text` vs. `tool-call`), not just one field's
    /// text, so this brace-matches from that point to isolate exactly the
    /// JSON object -- ignoring any trailing bytes -- and parses it with
    /// `JSONSerialization`. Returns `nil` for a blob that carries no such
    /// object (e.g. the root blob, which is pure protobuf) or one whose
    /// isolated span still fails to parse.
    static func messageObject(from data: Data) -> [String: Any]? {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "{\"")?.lowerBound,
              let span = balancedJSONObject(in: text, startingAt: start),
              let object = try? JSONSerialization.jsonObject(
                  with: Data(span.utf8)
              ) as? [String: Any]
        else { return nil }
        return object
    }

    /// Scans forward from `start` (the opening `{` of a JSON object)
    /// tracking brace depth and string state (so a `{`/`}` inside a quoted
    /// string, escaped or not, is never mistaken for structure), returning
    /// the smallest well-formed object span. Malformed input (unterminated
    /// string, brace that never closes) yields `nil`.
    private static func balancedJSONObject(
        in text: String,
        startingAt start: String.Index
    ) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// A blob's content array element carries this `type` when the
    /// message has real prompt/reply text -- distinct from `reasoning`,
    /// `tool-call`, and `tool-result` elements.
    private static func hasTextElement(_ content: [[String: Any]]) -> Bool {
        content.contains { ($0["type"] as? String) == "text" }
    }

    private static func hasToolCallElement(_ content: [[String: Any]]) -> Bool {
        content.contains { ($0["type"] as? String) == "tool-call" }
    }

    /// How many of a conversation's newest blobs (by rowid, i.e. insertion
    /// order) a single poll scans for the model name, context usage, and
    /// turn lifecycle. A real conversation only ever needs a handful of
    /// the newest rows to answer all three, and this bound keeps a very
    /// long conversation from turning every 5-second poll tick (Cursor
    /// uses the timed cache, see `AgentSessionThrottleCache`) into a full
    /// `blobs` table scan.
    static let maximumScannedBlobs = 400

    /// Reduces the conversation's newest blobs to the current prompt-turn's
    /// lifecycle, mirroring the `UserPromptSubmit`-to-`Stop` cycle a real
    /// hook integration reports, using the sequence verified against real
    /// `store.db` conversations: a `system` blob, an environment/context
    /// `user` blob with no `text` content element, then a real `user`
    /// prompt (a `text` content element) -- followed by zero or more
    /// `assistant` tool-call / `tool` result pairs -- and finally an
    /// `assistant` blob with a `text` element and no `tool-call` element,
    /// which completes the turn. So: scanning newest-first, an assistant
    /// blob shaped like that completion marker, seen before the newest
    /// real user prompt, means the turn is `.completed`; otherwise (the
    /// newest role-bearing blob is a tool-call or tool-result, or nothing
    /// followed the prompt at all) it's still `.active`. Cursor writes no
    /// marker for an interrupted turn, so this never returns
    /// `.interrupted` -- see `CursorConversationSnapshot.turn`. The turn
    /// key is the conversation ID plus the prompt blob's own rowid (not a
    /// hash of its text), since two identical prompts in one conversation
    /// must not collide. `nil` when the scanned blobs carry no real user
    /// prompt at all, or `conversationID` itself couldn't be resolved.
    static func turn(
        blobs: [(rowid: Int64, data: Data)],
        conversationID: String?
    ) -> AgentTurnObservation? {
        guard let conversationID else { return nil }

        var sawCompletionSinceNewest = false
        for blob in blobs {
            guard let message = messageObject(from: blob.data) else {
                continue
            }
            let role = message["role"] as? String
            let content = message["content"] as? [[String: Any]] ?? []

            if role == "assistant",
               hasTextElement(content),
               !hasToolCallElement(content) {
                sawCompletionSinceNewest = true
            } else if role == "user", hasTextElement(content) {
                guard let key = AgentSessionValidation.identifier(
                    "\(conversationID)#\(blob.rowid)"
                ) else { return nil }
                return AgentTurnObservation(
                    key: key,
                    phase: sawCompletionSinceNewest ? .completed : .active
                )
            }
        }
        return nil
    }

    /// Parses the context-usage record Cursor CLI writes into a
    /// conversation's newest "root" blob. That blob's top-level field 5
    /// (length-delimited) contains a nested message with field 1 (varint,
    /// used tokens) and field 2 (varint, context window total); other
    /// top-level and nested fields are ignored. This is untrusted data read
    /// from a local database, so every step is bounds-checked and malformed
    /// input yields `nil` rather than trapping.
    static func extractContextUsage(
        from data: Data
    ) -> (used: Double, total: Double)? {
        guard let field5 = topLevelField5(in: [UInt8](data)) else {
            return nil
        }
        return parseContextUsageMessage(field5)
    }

    /// Scans the top-level fields of a protobuf message for field 5
    /// (wire type 2) and returns its raw bytes. Returns `nil` if field 5
    /// is absent or the buffer is malformed.
    private static func topLevelField5(in bytes: [UInt8]) -> [UInt8]? {
        var index = 0
        while index < bytes.count {
            guard let (key, keyLength) = readVarint(bytes, at: index) else {
                return nil
            }
            index += keyLength
            let fieldNumber = key >> 3
            let wireType = key & 0x7

            switch wireType {
            case 0: // varint
                guard let (_, length) = readVarint(bytes, at: index) else {
                    return nil
                }
                index += length
            case 1: // 64-bit
                guard index + 8 <= bytes.count else { return nil }
                index += 8
            case 2: // length-delimited
                guard let (rawLength, lengthLength) = readVarint(
                    bytes,
                    at: index
                ) else { return nil }
                index += lengthLength
                guard rawLength <= UInt64(bytes.count - index) else {
                    return nil
                }
                let length = Int(rawLength)
                if fieldNumber == 5 {
                    return Array(bytes[index..<(index + length)])
                }
                index += length
            case 5: // 32-bit
                guard index + 4 <= bytes.count else { return nil }
                index += 4
            default: // 3, 4, 6, 7: not used by this format
                return nil
            }
        }
        return nil
    }

    /// Parses the field-5 sub-message for the used/total token counts.
    private static func parseContextUsageMessage(
        _ bytes: [UInt8]
    ) -> (used: Double, total: Double)? {
        var used: UInt64?
        var total: UInt64?
        var index = 0

        while index < bytes.count {
            guard let (key, keyLength) = readVarint(bytes, at: index) else {
                return nil
            }
            index += keyLength
            let fieldNumber = key >> 3
            let wireType = key & 0x7

            switch wireType {
            case 0: // varint
                guard let (value, length) = readVarint(bytes, at: index)
                else { return nil }
                index += length
                if fieldNumber == 1 {
                    used = value
                } else if fieldNumber == 2 {
                    total = value
                }
            case 1: // 64-bit
                guard index + 8 <= bytes.count else { return nil }
                index += 8
            case 2: // length-delimited (e.g. field 3, per-category breakdown)
                guard let (rawLength, lengthLength) = readVarint(
                    bytes,
                    at: index
                ) else { return nil }
                index += lengthLength
                guard rawLength <= UInt64(bytes.count - index) else {
                    return nil
                }
                index += Int(rawLength)
            case 5: // 32-bit
                guard index + 4 <= bytes.count else { return nil }
                index += 4
            default:
                return nil
            }
        }

        guard let used, let total,
              total > 0,
              total <= 100_000_000
        else { return nil }
        return (Double(used), Double(total))
    }

    /// Bounds-checked protobuf varint reader: reads at most 10 bytes (the
    /// maximum encoding length of a 64-bit value) starting at `start`, and
    /// never reads past the end of `bytes`. Returns `nil` on truncation or
    /// an over-long varint rather than trapping.
    private static func readVarint(
        _ bytes: [UInt8],
        at start: Int
    ) -> (value: UInt64, length: Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var offset = 0
        while offset < 10 {
            let position = start + offset
            guard position < bytes.count else { return nil }
            let byte = bytes[position]
            value |= UInt64(byte & 0x7F) << shift
            offset += 1
            if byte & 0x80 == 0 {
                return (value, offset)
            }
            shift += 7
        }
        return nil
    }

    private static func conversationDirectory(
        sessionID: String?,
        workingDirectory: URL?,
        chatsDirectory: URL
    ) -> URL? {
        if let sessionID = AgentSessionValidation.identifier(sessionID) {
            return findConversationDirectory(
                sessionID: sessionID,
                chatsDirectory: chatsDirectory
            )
        }
        guard let workingDirectory else { return nil }
        return newestConversationDirectory(
            matchingWorkingDirectory: workingDirectory.standardizedFileURL,
            chatsDirectory: chatsDirectory
        )
    }

    private static func findConversationDirectory(
        sessionID: String,
        chatsDirectory: URL
    ) -> URL? {
        guard let workspaceDirectories = try? FileManager.default
            .contentsOfDirectory(
                at: chatsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return nil }

        for workspaceDirectory in workspaceDirectories {
            let candidate = workspaceDirectory
                .appendingPathComponent(sessionID, isDirectory: true)
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("store.db").path
            ) {
                return candidate
            }
        }
        return nil
    }

    private static func newestConversationDirectory(
        matchingWorkingDirectory workingDirectory: URL,
        chatsDirectory: URL
    ) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: chatsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Compare plain paths: URL equality would also require matching
        // trailing slashes, which URL(fileURLWithPath:) only adds when the
        // path exists on disk as a directory.
        let workingDirectoryPath = workingDirectory.path
        var best: (directory: URL, updatedAtMs: Double)?
        for case let metaFile as URL in enumerator
        where metaFile.lastPathComponent == "meta.json" {
            guard let data = try? Data(contentsOf: metaFile),
                  let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let cwd = object["cwd"] as? String,
                  URL(fileURLWithPath: cwd).standardizedFileURL.path
                    == workingDirectoryPath
            else { continue }
            let updatedAtMs = (object["updatedAtMs"] as? NSNumber)?
                .doubleValue ?? 0
            if best == nil || updatedAtMs > best!.updatedAtMs {
                best = (metaFile.deletingLastPathComponent(), updatedAtMs)
            }
        }
        return best?.directory
    }

    /// Scans a conversation's `maximumScannedBlobs` newest blobs (by
    /// rowid) for the model name, the context-usage record, and the
    /// current turn -- one query, one connection, reused for everything a
    /// poll tick needs (`CursorProviderRuntime.poll` calls this exactly
    /// once per tick, same as before turn/mode support was added). The
    /// model name and context-usage record may live in different blobs (a
    /// message blob for the model name, the newest root blob for context
    /// usage), and the turn's real prompt may be further back still than
    /// either -- so unlike the pre-turn version of this scan, there is no
    /// early break once model/context are found; `maximumScannedBlobs`
    /// itself (applied as the query's `LIMIT`) is what bounds the work.
    /// `mode` comes from a second, equally cheap query against `meta` in
    /// the same connection -- still one database *open* per poll, which is
    /// what actually costs (WAL/immutable-retry, page cache warmup).
    private static func latestConversationDetails(
        storeDatabaseURL: URL,
        conversationID: String?
    ) -> (
        modelName: String?,
        contextUsage: (used: Double, total: Double)?,
        turn: AgentTurnObservation?,
        mode: String?
    ) {
        AgentSessionDatabase.withReadOnlyConnection(
            at: storeDatabaseURL
        ) { database -> (
            modelName: String?,
            contextUsage: (used: Double, total: Double)?,
            turn: AgentTurnObservation?,
            mode: String?
        )? in
            guard AgentSessionDatabase.hasTable("blobs", database: database)
            else { return nil }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT rowid, data FROM blobs ORDER BY rowid DESC LIMIT \(maximumScannedBlobs);",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }

            var modelName: String?
            var contextUsage: (used: Double, total: Double)?
            var blobs: [(rowid: Int64, data: Data)] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let rowid = sqlite3_column_int64(statement, 0)
                guard let bytes = sqlite3_column_blob(statement, 1) else {
                    continue
                }
                let length = Int(sqlite3_column_bytes(statement, 1))
                let data = Data(bytes: bytes, count: length)

                if modelName == nil,
                   let name = extractModelName(from: data) {
                    modelName = name
                }
                if contextUsage == nil,
                   let usage = extractContextUsage(from: data) {
                    contextUsage = usage
                }
                blobs.append((rowid: rowid, data: data))
            }

            return (
                modelName,
                contextUsage,
                turn(blobs: blobs, conversationID: conversationID),
                mode(database: database)
            )
        } ?? (nil, nil, nil, nil)
    }

    /// Reads the conversation's `mode` from its single `meta` row, if the
    /// table exists at all -- older Cursor CLI versions may not write one.
    private static func mode(database: OpaquePointer) -> String? {
        guard AgentSessionDatabase.hasTable("meta", database: database)
        else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM meta LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0)
        else { return nil }
        let length = Int(sqlite3_column_bytes(statement, 0))
        return extractMode(from: Data(bytes: bytes, count: length))
    }
}
