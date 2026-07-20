import Foundation
import SQLite3

/// Reads the model name Cursor most recently used in a chat conversation.
/// Cursor does not persist a usable context window budget locally, so
/// `contextRemainingPercent` is always `nil`.
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
        guard let modelName = latestModelName(
            storeDatabaseURL: conversationDirectory
                .appendingPathComponent("store.db")
        ) else { return nil }

        let resolvedSessionID = AgentSessionValidation.identifier(sessionID)
            ?? AgentSessionValidation.identifier(
                conversationDirectory.lastPathComponent
            )
        return AgentSessionStatus(
            sessionID: resolvedSessionID,
            modelName: modelName,
            contextRemainingPercent: nil
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

    private static func latestModelName(storeDatabaseURL: URL) -> String? {
        AgentSessionDatabase.withReadOnlyConnection(
            at: storeDatabaseURL
        ) { database in
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

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else {
                    continue
                }
                let length = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: bytes, count: length)
                if let modelName = extractModelName(from: data) {
                    return modelName
                }
            }
            return nil
        }
    }
}
