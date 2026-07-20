import Foundation
import SQLite3

/// Reads the model name of the most recent assistant message for a given
/// OpenCode session. OpenCode does not persist a context window size
/// locally, so `contextRemainingPercent` is always `nil` and the status bar
/// meter stays hidden for this provider.
public enum OpenCodeSessionInspector {
    public static func status(
        sessionID: String?,
        databaseURL: URL = defaultDatabaseURL
    ) -> AgentSessionStatus? {
        guard let sessionID = AgentSessionValidation.identifier(sessionID)
        else { return nil }
        guard let modelName = latestModelName(
            sessionID: sessionID,
            databaseURL: databaseURL
        ) else { return nil }
        return AgentSessionStatus(
            sessionID: sessionID,
            modelName: modelName,
            contextRemainingPercent: nil
        )
    }

    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(
                path: ".local/share/opencode/opencode.db",
                directoryHint: .notDirectory
            )
    }

    private static func latestModelName(
        sessionID: String,
        databaseURL: URL
    ) -> String? {
        AgentSessionDatabase.withReadOnlyConnection(
            at: databaseURL
        ) { database in
            guard AgentSessionDatabase.hasTable(
                "message",
                database: database
            ) else { return nil }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                latestModelQuery,
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(
                -1,
                to: sqlite3_destructor_type.self
            )
            sqlite3_bind_text(statement, 1, sessionID, -1, transient)

            guard sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0)
            else { return nil }
            return AgentSessionValidation.label(String(cString: text))
        }
    }

    private static let latestModelQuery = """
        SELECT json_extract(data, '$.modelID')
        FROM message
        WHERE session_id = ?
          AND json_valid(data)
          AND json_extract(data, '$.role') = 'assistant'
        ORDER BY time_created DESC
        LIMIT 1;
        """
}
