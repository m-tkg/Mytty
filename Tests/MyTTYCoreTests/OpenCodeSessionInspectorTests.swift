import Foundation
import SQLite3
import Testing

@testable import MyTTYCore

@Suite("OpenCode session inspection")
struct OpenCodeSessionInspectorTests {
    @Test("reads the model of the latest assistant message for a session")
    func latestModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("opencode.db")

        try makeDatabase(at: databaseURL) { database in
            try insertMessage(
                into: database,
                id: "msg-1",
                sessionID: "opencode-session",
                createdAtMilliseconds: 1_000,
                role: "assistant",
                modelID: "older-model"
            )
            try insertMessage(
                into: database,
                id: "msg-2",
                sessionID: "opencode-session",
                createdAtMilliseconds: 2_000,
                role: "assistant",
                modelID: "newer-model"
            )
            try insertMessage(
                into: database,
                id: "msg-3",
                sessionID: "other-session",
                createdAtMilliseconds: 3_000,
                role: "assistant",
                modelID: "unrelated-model"
            )
        }

        let status = OpenCodeSessionInspector.status(
            sessionID: "opencode-session",
            databaseURL: databaseURL
        )
        #expect(status?.sessionID == "opencode-session")
        #expect(status?.modelName == "newer-model")
        #expect(status?.contextRemainingPercent == nil)
    }

    @Test("returns nil without a hook session ID")
    func requiresSessionID() {
        #expect(
            OpenCodeSessionInspector.status(
                sessionID: nil,
                databaseURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("missing.db")
            ) == nil
        )
    }

    @Test("returns nil when the database does not exist")
    func missingDatabase() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
        #expect(
            OpenCodeSessionInspector.status(
                sessionID: "opencode-session",
                databaseURL: missing
            ) == nil
        )
    }

    private func makeDatabase(
        at url: URL,
        populate: (OpaquePointer) throws -> Void
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK, let database else {
            struct OpenFailure: Error {}
            throw OpenFailure()
        }
        defer { sqlite3_close(database) }

        try exec(
            database,
            """
            CREATE TABLE message (
              id text PRIMARY KEY,
              session_id text NOT NULL,
              time_created integer NOT NULL,
              time_updated integer NOT NULL,
              data text NOT NULL
            );
            """
        )
        try populate(database)
    }

    private func insertMessage(
        into database: OpaquePointer,
        id: String,
        sessionID: String,
        createdAtMilliseconds: Int64,
        role: String,
        modelID: String
    ) throws {
        let data = """
        {"role":"\(role)","modelID":"\(modelID)"}
        """
        try exec(
            database,
            """
            INSERT INTO message (id, session_id, time_created, time_updated, data)
            VALUES ('\(id)', '\(sessionID)', \(createdAtMilliseconds), \(createdAtMilliseconds), '\(data)');
            """
        )
    }

    private func exec(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            struct ExecFailure: Error {
                let message: String
            }
            let message = String(cString: sqlite3_errmsg(database))
            throw ExecFailure(message: message)
        }
    }
}
