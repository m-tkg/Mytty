import Foundation
import Testing

@testable import MyTTYCore

struct SQLiteRepositoryFailureTests {
    @Test("repositories preserve their error types and messages for invalid databases")
    func invalidDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("invalid.sqlite")
        try Data(repeating: 0x61, count: 512).write(to: database)

        #expect(throws: SessionRepositoryError.database("file is not a database")) {
            try SQLiteSessionRepository(databaseURL: database).load()
        }
        #expect(throws: AgentEventRepositoryError.database("file is not a database")) {
            try SQLiteAgentEventRepository(databaseURL: database).loadEvents()
        }
        #expect(throws: PaneInputScheduleRepositoryError.database("file is not a database")) {
            try SQLitePaneInputScheduleRepository(databaseURL: database).load()
        }
    }

    @Test("repositories preserve their error types and messages when opening a directory")
    func directoryAsDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: SessionRepositoryError.database("unable to open database file")) {
            try SQLiteSessionRepository(databaseURL: root).load()
        }
        #expect(throws: AgentEventRepositoryError.database("unable to open database file")) {
            try SQLiteAgentEventRepository(databaseURL: root).loadEvents()
        }
        #expect(throws: PaneInputScheduleRepositoryError.database("unable to open database file")) {
            try SQLitePaneInputScheduleRepository(databaseURL: root).load()
        }
    }
}
