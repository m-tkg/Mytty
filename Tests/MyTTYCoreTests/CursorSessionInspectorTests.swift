import Foundation
import SQLite3
import Testing

@testable import MyTTYCore

@Suite("Cursor session inspection")
struct CursorSessionInspectorTests {
    @Test("extracts modelName from a blob with a binary prefix")
    func extractsModelName() {
        var data = Data([0x00, 0x01, 0xFF, 0x02])
        data.append(Data("""
        {"role":"assistant","providerOptions":{"cursor":{"modelName":"cursor-grok-4.5-high"}}}
        """.utf8))

        #expect(
            CursorSessionInspector.extractModelName(from: data)
                == "cursor-grok-4.5-high"
        )
        #expect(
            CursorSessionInspector.extractModelName(from: Data("{}".utf8))
                == nil
        )
    }

    @Test("finds the conversation directory by session ID and reads the latest blob's model")
    func findsBySessionID() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursorHome = root.appendingPathComponent(".cursor", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let conversationDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/cursor-session-id",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: conversationDirectory,
            withIntermediateDirectories: true
        )
        let databaseURL = conversationDirectory
            .appendingPathComponent("store.db")
        try makeStoreDatabase(at: databaseURL) { database in
            try insertBlob(
                into: database,
                id: "blob-1",
                json: """
                {"providerOptions":{"cursor":{"modelName":"older-model"}}}
                """
            )
            try insertBlob(
                into: database,
                id: "blob-2",
                json: """
                {"providerOptions":{"cursor":{"modelName":"newer-model"}}}
                """
            )
        }

        let status = CursorSessionInspector.status(
            sessionID: "cursor-session-id",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(status?.sessionID == "cursor-session-id")
        #expect(status?.modelName == "newer-model")
        #expect(status?.contextRemainingPercent == nil)
    }

    @Test("falls back to the newest meta.json whose cwd matches the working directory")
    func fallsBackToWorkingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursorHome = root.appendingPathComponent(".cursor", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Deliberately not created on disk: URL(fileURLWithPath:) treats
        // unknown paths as files, which is what the inspector sees on a
        // machine where the recorded cwd does not exist.
        let workingDirectory = root.appendingPathComponent(
            "workspace-not-on-disk",
            isDirectory: true
        )

        let staleDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/stale-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: staleDirectory,
            withIntermediateDirectories: true
        )
        try writeMeta(
            at: staleDirectory,
            cwd: workingDirectory.path,
            updatedAtMs: 1_000
        )
        try makeStoreDatabase(
            at: staleDirectory.appendingPathComponent("store.db")
        ) { database in
            try insertBlob(
                into: database,
                id: "blob-1",
                json: """
                {"providerOptions":{"cursor":{"modelName":"stale-model"}}}
                """
            )
        }

        let freshDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/fresh-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: freshDirectory,
            withIntermediateDirectories: true
        )
        try writeMeta(
            at: freshDirectory,
            cwd: workingDirectory.path,
            updatedAtMs: 2_000
        )
        try makeStoreDatabase(
            at: freshDirectory.appendingPathComponent("store.db")
        ) { database in
            try insertBlob(
                into: database,
                id: "blob-1",
                json: """
                {"providerOptions":{"cursor":{"modelName":"fresh-model"}}}
                """
            )
        }

        let otherCwdDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/other-cwd-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: otherCwdDirectory,
            withIntermediateDirectories: true
        )
        try writeMeta(
            at: otherCwdDirectory,
            cwd: "/some/other/project",
            updatedAtMs: 9_000
        )

        let status = CursorSessionInspector.status(
            sessionID: nil,
            workingDirectory: workingDirectory,
            cursorHome: cursorHome
        )
        #expect(status?.sessionID == "fresh-session")
        #expect(status?.modelName == "fresh-model")
    }

    @Test("reads a WAL-mode database whose sidecars were checkpointed away")
    func readsCheckpointedWALDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursorHome = root.appendingPathComponent(".cursor", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let conversationDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/wal-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: conversationDirectory,
            withIntermediateDirectories: true
        )
        let databaseURL = conversationDirectory
            .appendingPathComponent("store.db")
        try makeStoreDatabase(at: databaseURL, journalMode: "WAL") { database in
            try insertBlob(
                into: database,
                id: "blob-1",
                json: """
                {"providerOptions":{"cursor":{"modelName":"wal-model"}}}
                """
            )
        }
        // Cursor leaves the database header in WAL mode with no sidecars;
        // a plain read-only connection cannot query such a file.
        for sidecar in ["store.db-wal", "store.db-shm"] {
            try? FileManager.default.removeItem(
                at: conversationDirectory.appendingPathComponent(sidecar)
            )
        }

        #expect(
            CursorSessionInspector.status(
                sessionID: "wal-session",
                workingDirectory: nil,
                cursorHome: cursorHome
            )?.modelName == "wal-model"
        )
    }

    @Test("returns nil when there is no matching conversation directory")
    func missingConversation() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(
            CursorSessionInspector.status(
                sessionID: "unknown-session",
                workingDirectory: nil,
                cursorHome: missing
            ) == nil
        )
        #expect(
            CursorSessionInspector.status(
                sessionID: nil,
                workingDirectory: nil,
                cursorHome: missing
            ) == nil
        )
    }

    @Test("extracts context usage from a root blob's field-5 record and computes remaining percent")
    func extractsContextUsage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursorHome = root.appendingPathComponent(".cursor", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let conversationDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/context-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: conversationDirectory,
            withIntermediateDirectories: true
        )
        try makeStoreDatabase(
            at: conversationDirectory.appendingPathComponent("store.db")
        ) { database in
            try insertBlob(
                into: database,
                id: "blob-1",
                json: """
                {"providerOptions":{"cursor":{"modelName":"context-model"}}}
                """
            )
            try insertRootBlob(
                into: database,
                id: "blob-2",
                usedTokens: 13509,
                totalTokens: 256_000
            )
        }

        let status = CursorSessionInspector.status(
            sessionID: "context-session",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(status?.modelName == "context-model")
        // 13509 / 256000 * 100 = 5.277... -> rounded 5 -> 100 - 5 = 95
        #expect(status?.contextRemainingPercent == 95)
    }

    @Test("returns a nil percent when no root blob carries context usage")
    func noRootBlobMeansNilPercent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursorHome = root.appendingPathComponent(".cursor", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let conversationDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/no-root-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: conversationDirectory,
            withIntermediateDirectories: true
        )
        try makeStoreDatabase(
            at: conversationDirectory.appendingPathComponent("store.db")
        ) { database in
            try insertBlob(
                into: database,
                id: "blob-1",
                json: """
                {"providerOptions":{"cursor":{"modelName":"only-model"}}}
                """
            )
        }

        let status = CursorSessionInspector.status(
            sessionID: "no-root-session",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(status?.modelName == "only-model")
        #expect(status?.contextRemainingPercent == nil)
    }

    @Test("newer root blob wins over an older one")
    func newestRootBlobWins() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursorHome = root.appendingPathComponent(".cursor", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let conversationDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/rowid-order-session",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: conversationDirectory,
            withIntermediateDirectories: true
        )
        try makeStoreDatabase(
            at: conversationDirectory.appendingPathComponent("store.db")
        ) { database in
            // Inserted first -> lower rowid -> older.
            try insertRootBlob(
                into: database,
                id: "blob-older",
                usedTokens: 1_000,
                totalTokens: 100_000
            )
            // Inserted second -> higher rowid -> newer, should win.
            try insertRootBlob(
                into: database,
                id: "blob-newer",
                usedTokens: 13509,
                totalTokens: 256_000
            )
            try insertBlob(
                into: database,
                id: "blob-model",
                json: """
                {"providerOptions":{"cursor":{"modelName":"rowid-model"}}}
                """
            )
        }

        let status = CursorSessionInspector.status(
            sessionID: "rowid-order-session",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(status?.contextRemainingPercent == 95)
    }

    @Test("extractContextUsage rejects malformed or edge-case protobuf data")
    func extractContextUsageEdgeCases() {
        // Truncated varint (continuation bit set, buffer ends).
        #expect(
            CursorSessionInspector.extractContextUsage(
                from: Data([0x2A, 0x02, 0x08, 0x80])
            ) == nil
        )

        // Declared length exceeds remaining buffer.
        #expect(
            CursorSessionInspector.extractContextUsage(
                from: Data([0x2A, 0x7F, 0x08, 0x01])
            ) == nil
        )

        // total == 0 -> nil.
        let zeroTotal = encodeRootBlob(usedTokens: 100, totalTokens: 0)
        #expect(CursorSessionInspector.extractContextUsage(from: zeroTotal) == nil)

        // used > total -> percent clamps to 0, still returns a usage pair.
        let overUsed = encodeRootBlob(usedTokens: 300_000, totalTokens: 256_000)
        let usage = CursorSessionInspector.extractContextUsage(from: overUsed)
        #expect(usage != nil)
        if let usage {
            let percent = 100 - min(
                100,
                max(0, (usage.used / usage.total * 100).rounded())
            )
            #expect(percent == 0)
        }

        // Plain JSON blob (starts with '{' = 0x7B) has no field-5 message.
        #expect(
            CursorSessionInspector.extractContextUsage(
                from: Data("""
                {"role":"assistant","providerOptions":{"cursor":{"modelName":"x"}}}
                """.utf8)
            ) == nil
        )
    }

    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func encodeKey(fieldNumber: Int, wireType: Int) -> [UInt8] {
        encodeVarint(UInt64((fieldNumber << 3) | wireType))
    }

    /// Encodes a root blob's field-5 sub-message
    /// (1: usedTokens, 2: totalTokens) wrapped as a top-level field 5,
    /// mirroring the real Cursor store.db root blob layout.
    private func encodeRootBlob(
        usedTokens: UInt64,
        totalTokens: UInt64
    ) -> Data {
        var inner: [UInt8] = []
        inner += encodeKey(fieldNumber: 1, wireType: 0)
        inner += encodeVarint(usedTokens)
        inner += encodeKey(fieldNumber: 2, wireType: 0)
        inner += encodeVarint(totalTokens)

        var outer: [UInt8] = []
        outer += encodeKey(fieldNumber: 5, wireType: 2)
        outer += encodeVarint(UInt64(inner.count))
        outer += inner
        return Data(outer)
    }

    private func insertRootBlob(
        into database: OpaquePointer,
        id: String,
        usedTokens: UInt64,
        totalTokens: UInt64
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO blobs (id, data) VALUES (?, ?);",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            struct PrepareFailure: Error {}
            throw PrepareFailure()
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient)
        let data = Array(encodeRootBlob(
            usedTokens: usedTokens,
            totalTokens: totalTokens
        ))
        sqlite3_bind_blob(statement, 2, data, Int32(data.count), transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            struct StepFailure: Error {}
            throw StepFailure()
        }
    }

    private func writeMeta(
        at directory: URL,
        cwd: String,
        updatedAtMs: Int
    ) throws {
        let meta = """
        {"cwd":"\(cwd)","updatedAtMs":\(updatedAtMs)}
        """
        try meta.write(
            to: directory.appendingPathComponent("meta.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func makeStoreDatabase(
        at url: URL,
        journalMode: String? = nil,
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

        if let journalMode {
            try exec(database, "PRAGMA journal_mode = \(journalMode);")
        }
        try exec(
            database,
            """
            CREATE TABLE blobs (id TEXT PRIMARY KEY, data BLOB);
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
            """
        )
        try populate(database)
    }

    private func insertBlob(
        into database: OpaquePointer,
        id: String,
        json: String
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO blobs (id, data) VALUES (?, ?);",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            struct PrepareFailure: Error {}
            throw PrepareFailure()
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient)
        let data = Array(json.utf8)
        sqlite3_bind_blob(statement, 2, data, Int32(data.count), transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            struct StepFailure: Error {}
            throw StepFailure()
        }
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
