import Foundation
import SQLite3

/// Shared SQLite mechanics; repositories retain their schemas and public errors.
protocol SQLiteRepository {
    associatedtype DatabaseFailure: Error

    var databaseURL: URL { get }
    static func makeDatabaseError(_ message: String) -> DatabaseFailure
}

extension SQLiteRepository {
    func withConnection<T>(
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE
            | SQLITE_OPEN_READWRITE
            | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            flags,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map(databaseMessage) ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            throw Self.makeDatabaseError(message)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 1_000)
        return try body(database)
    }

    func execute(
        _ sql: String,
        in database: OpaquePointer
    ) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
    }

    func prepare(
        _ sql: String,
        in database: OpaquePointer
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        let statement else {
            throw databaseError(database)
        }
        return statement
    }

    func databaseError(
        _ database: OpaquePointer
    ) -> DatabaseFailure {
        Self.makeDatabaseError(databaseMessage(database))
    }

    func databaseMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
