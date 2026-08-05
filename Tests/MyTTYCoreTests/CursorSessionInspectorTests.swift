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

    // MARK: - Turn detection

    @Test("a real prompt followed by a tool-call/tool-result pair is active")
    func turnActiveAfterToolCall() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "turn-active") { database in
            try insertBlob(into: database, id: "b1", json: """
            {"role":"system","content":[]}
            """)
            try insertBlob(into: database, id: "b2", json: """
            {"role":"user","content":[{"type":"environment","value":"cwd"}]}
            """)
            try insertBlob(into: database, id: "b3", json: """
            {"role":"user","content":[{"type":"text","text":"do the thing"}]}
            """)
            try insertBlob(into: database, id: "b4", json: """
            {"role":"assistant","content":[{"type":"tool-call","toolName":"bash"}]}
            """)
            try insertBlob(into: database, id: "b5", json: """
            {"role":"tool","content":[{"type":"tool-result","toolName":"bash"}]}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "turn-active",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn?.key == "turn-active#3")
        #expect(snapshot.turn?.phase == .active)
    }

    @Test("an assistant text reply with no tool-call completes the turn")
    func turnCompletedAfterAssistantText() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "turn-completed") { database in
            try insertBlob(into: database, id: "b1", json: """
            {"role":"system","content":[]}
            """)
            try insertBlob(into: database, id: "b2", json: """
            {"role":"user","content":[{"type":"text","text":"do the thing"}]}
            """)
            try insertBlob(into: database, id: "b3", json: """
            {"role":"assistant","content":[{"type":"tool-call","toolName":"bash"}]}
            """)
            try insertBlob(into: database, id: "b4", json: """
            {"role":"tool","content":[{"type":"tool-result","toolName":"bash"}]}
            """)
            try insertBlob(into: database, id: "b5", json: """
            {"role":"assistant","content":[{"type":"text","text":"done"}]}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "turn-completed",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn?.key == "turn-completed#2")
        #expect(snapshot.turn?.phase == .completed)
    }

    @Test("a context-only user blob with no text element yields no turn")
    func contextOnlyBlobYieldsNilTurn() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "context-only") { database in
            try insertBlob(into: database, id: "b1", json: """
            {"role":"system","content":[]}
            """)
            try insertBlob(into: database, id: "b2", json: """
            {"role":"user","content":[{"type":"environment","value":"cwd"}]}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "context-only",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn == nil)
    }

    @Test("the newer of two prompts wins, with a distinct key from the older one's")
    func newerPromptWinsWithDistinctKey() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "two-prompts") { database in
            try insertBlob(into: database, id: "b1", json: """
            {"role":"system","content":[]}
            """)
            try insertBlob(into: database, id: "b2", json: """
            {"role":"user","content":[{"type":"text","text":"first"}]}
            """)
            try insertBlob(into: database, id: "b3", json: """
            {"role":"assistant","content":[{"type":"text","text":"done with first"}]}
            """)
            try insertBlob(into: database, id: "b4", json: """
            {"role":"user","content":[{"type":"text","text":"second"}]}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "two-prompts",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn?.key == "two-prompts#4")
        #expect(snapshot.turn?.key != "two-prompts#2")
        #expect(snapshot.turn?.phase == .active)
    }

    @Test("identical prompt text at different rowids yields distinct turn keys")
    func identicalPromptTextYieldsDistinctKeys() {
        let promptData = Data("""
        {"role":"user","content":[{"type":"text","text":"same text"}]}
        """.utf8)

        let older = CursorSessionInspector.turn(
            blobs: [(rowid: 2, data: promptData)],
            conversationID: "conv"
        )
        let newer = CursorSessionInspector.turn(
            blobs: [(rowid: 7, data: promptData)],
            conversationID: "conv"
        )
        #expect(older?.key == "conv#2")
        #expect(newer?.key == "conv#7")
        #expect(older?.key != newer?.key)
    }

    @Test("a message blob with a binary prefix before the JSON still parses for turn detection")
    func binaryPrefixedMessageBlobParses() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "prefixed") { database in
            var promptBytes = Data([0x00, 0x01, 0xFF, 0x02])
            promptBytes.append(Data("""
            {"role":"user","content":[{"type":"text","text":"do the thing"}]}
            """.utf8))
            try insertBlobData(into: database, id: "b1", data: promptBytes)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "prefixed",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn?.key == "prefixed#1")
        #expect(snapshot.turn?.phase == .active)
    }

    @Test("malformed or non-JSON blobs are skipped rather than failing the read")
    func malformedBlobsAreSkipped() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "malformed") { database in
            try insertBlob(into: database, id: "garbage1", json: "not json at all")
            try insertBlobData(
                into: database,
                id: "garbage2",
                data: Data([0x00, 0x01, 0x02, 0x03])
            )
            try insertBlob(into: database, id: "prompt", json: """
            {"role":"user","content":[{"type":"text","text":"do the thing"}]}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "malformed",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn?.key == "malformed#3")
        #expect(snapshot.turn?.phase == .active)
    }

    @Test("more blobs than the scan cap still reports the newest turn")
    func scanBoundStillReportsNewestTurn() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        let fillerCount = CursorSessionInspector.maximumScannedBlobs + 50
        try makeConversation(cursorHome: cursorHome, sessionID: "bounded") { database in
            for index in 0..<fillerCount {
                try insertBlob(into: database, id: "filler-\(index)", json: """
                {"role":"system","content":[]}
                """)
            }
            try insertBlob(into: database, id: "prompt", json: """
            {"role":"user","content":[{"type":"text","text":"do the thing"}]}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "bounded",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.turn?.key == "bounded#\(fillerCount + 1)")
        #expect(snapshot.turn?.phase == .active)
    }

    // MARK: - Mode

    @Test("meta.mode = plan yields mode plan")
    func metaModePlan() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "mode-plan") { database in
            try insertMetaRow(into: database, json: """
            {"agentId":"a","mode":"plan","isRunEverything":false}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "mode-plan",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.mode == "plan")
    }

    @Test("a hex-transcribed meta row yields its mode")
    func metaModeHexEncoded() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        // How real Cursor databases store the row: the JSON's bytes
        // written out as hex text rather than as the JSON itself.
        let json = #"{"agentId":"a","mode":"ask","isRunEverything":false}"#
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()

        try makeConversation(cursorHome: cursorHome, sessionID: "mode-hex") { database in
            try insertMetaRow(into: database, json: hex)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "mode-hex",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.mode == "ask")
    }

    @Test("an unrecognized meta.mode value yields nil")
    func metaModeUnknownValueYieldsNil() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "mode-unknown") { database in
            try insertMetaRow(into: database, json: """
            {"agentId":"a","mode":"yolo"}
            """)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "mode-unknown",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.mode == nil)
    }

    @Test("a missing or garbage meta row yields nil mode")
    func metaModeMissingOrGarbageYieldsNil() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "mode-missing") { _ in
            // No meta row inserted at all.
        }
        #expect(
            CursorSessionInspector.snapshot(
                sessionID: "mode-missing",
                workingDirectory: nil,
                cursorHome: cursorHome
            ).mode == nil
        )

        try makeConversation(cursorHome: cursorHome, sessionID: "mode-garbage") { database in
            try insertMetaRow(into: database, json: "not json at all")
        }
        #expect(
            CursorSessionInspector.snapshot(
                sessionID: "mode-garbage",
                workingDirectory: nil,
                cursorHome: cursorHome
            ).mode == nil
        )
    }

    @Test("a binary-prefixed meta value still parses")
    func binaryPrefixedMetaValueParses() throws {
        let (cursorHome, root) = try makeCursorHome()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeConversation(cursorHome: cursorHome, sessionID: "mode-prefixed") { database in
            var metaBytes = Data([0x00, 0x01, 0xFF, 0x02])
            metaBytes.append(Data("""
            {"agentId":"a","mode":"ask"}
            """.utf8))
            try insertMetaData(into: database, data: metaBytes)
        }

        let snapshot = CursorSessionInspector.snapshot(
            sessionID: "mode-prefixed",
            workingDirectory: nil,
            cursorHome: cursorHome
        )
        #expect(snapshot.mode == "ask")
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
        try insertBlobData(into: database, id: id, data: Data(json.utf8))
    }

    /// Like `insertBlob(into:id:json:)`, but takes raw bytes -- used by the
    /// binary-prefix tests, which need to prepend non-UTF8 bytes ahead of
    /// the JSON payload the way a real Cursor blob sometimes does.
    private func insertBlobData(
        into database: OpaquePointer,
        id: String,
        data: Data
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
        let bytes = Array(data)
        sqlite3_bind_blob(statement, 2, bytes, Int32(bytes.count), transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            struct StepFailure: Error {}
            throw StepFailure()
        }
    }

    /// Inserts the conversation's single `meta` row (real `store.db`
    /// databases carry exactly one) with the given JSON text as its value.
    private func insertMetaRow(
        into database: OpaquePointer,
        json: String
    ) throws {
        try insertMetaData(into: database, data: Data(json.utf8))
    }

    /// Like `insertMetaRow(into:json:)`, but takes raw bytes -- used by the
    /// binary-prefix test. `meta.value` is declared `TEXT`, but SQLite's
    /// dynamic typing stores whatever bytes are bound regardless of the
    /// column's declared affinity, same as a real Cursor database might.
    private func insertMetaData(
        into database: OpaquePointer,
        data: Data
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO meta (key, value) VALUES (?, ?);",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            struct PrepareFailure: Error {}
            throw PrepareFailure()
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, "conversation", -1, transient)
        let bytes = Array(data)
        sqlite3_bind_blob(statement, 2, bytes, Int32(bytes.count), transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            struct StepFailure: Error {}
            throw StepFailure()
        }
    }

    /// A fresh temporary `.cursor` home for a test, alongside its root
    /// directory (the caller is responsible for removing `root` when done,
    /// same as every other test in this file).
    private func makeCursorHome() throws -> (cursorHome: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (root.appendingPathComponent(".cursor", isDirectory: true), root)
    }

    /// Creates a conversation directory (with a fixed, arbitrary
    /// workspace-hash component -- turn/mode tests never exercise the
    /// working-directory fallback, only lookup by session ID) and its
    /// `store.db`, populated by `populate`.
    private func makeConversation(
        cursorHome: URL,
        sessionID: String,
        populate: (OpaquePointer) throws -> Void
    ) throws {
        let conversationDirectory = cursorHome
            .appendingPathComponent(
                "chats/workspace-hash/\(sessionID)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: conversationDirectory,
            withIntermediateDirectories: true
        )
        try makeStoreDatabase(
            at: conversationDirectory.appendingPathComponent("store.db"),
            populate: populate
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
