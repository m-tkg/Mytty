import Foundation
import SQLite3

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
        let chatsDirectory = cursorHome
            .appendingPathComponent("chats", isDirectory: true)
        guard let conversationDirectory = conversationDirectory(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            chatsDirectory: chatsDirectory
        ) else { return nil }
        let details = latestSessionDetails(
            storeDatabaseURL: conversationDirectory
                .appendingPathComponent("store.db")
        )
        guard let modelName = details.modelName else { return nil }

        let resolvedSessionID = AgentSessionValidation.identifier(sessionID)
            ?? AgentSessionValidation.identifier(
                conversationDirectory.lastPathComponent
            )
        return AgentSessionStatus(
            sessionID: resolvedSessionID,
            modelName: modelName,
            contextRemainingPercent: details.contextUsage.map { usage in
                // Match Claude Code's convention: round the *used* share to
                // a whole percent and subtract it, rather than rounding the
                // remainder (see ClaudeCodeSessionInspector.status(from:)).
                100 - min(
                    100,
                    max(0, (usage.used / usage.total * 100).rounded())
                )
            }
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

    /// Scans a conversation's blobs newest-first for the model name and the
    /// context-usage record, stopping as soon as both have been found. The
    /// two facts may live in different blobs (a message blob for the model
    /// name, the newest root blob for context usage), so a single pass
    /// tracks whichever is still missing rather than scanning twice.
    private static func latestSessionDetails(
        storeDatabaseURL: URL
    ) -> (
        modelName: String?,
        contextUsage: (used: Double, total: Double)?
    ) {
        AgentSessionDatabase.withReadOnlyConnection(
            at: storeDatabaseURL
        ) { database -> (
            modelName: String?,
            contextUsage: (used: Double, total: Double)?
        )? in
            guard AgentSessionDatabase.hasTable("blobs", database: database)
            else { return nil }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT data FROM blobs ORDER BY rowid DESC;",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }

            var modelName: String?
            var contextUsage: (used: Double, total: Double)?

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else {
                    continue
                }
                let length = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: bytes, count: length)

                if modelName == nil,
                   let name = extractModelName(from: data) {
                    modelName = name
                }
                if contextUsage == nil,
                   let usage = extractContextUsage(from: data) {
                    contextUsage = usage
                }
                if modelName != nil && contextUsage != nil {
                    break
                }
            }
            return (modelName, contextUsage)
        } ?? (nil, nil)
    }
}
