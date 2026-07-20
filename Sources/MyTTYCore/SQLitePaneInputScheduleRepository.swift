import Foundation
import SQLite3

public enum PaneInputScheduleRepositoryError: Error, Equatable, Sendable {
    case database(String)
    case invalidIdentifier(String)
    case missingValue
}

public struct SQLitePaneInputScheduleRepository: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func load() throws -> [PaneInputSchedule] {
        try withDatabase { database in
            let statement = try prepare(
                """
                SELECT schedule_id, surface_id, fire_at, input_text,
                       append_newline
                FROM pane_input_schedule
                ORDER BY fire_at, schedule_id
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            var schedules: [PaneInputSchedule] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    schedules.append(try readSchedule(from: statement))
                case SQLITE_DONE:
                    return schedules
                default:
                    throw databaseError(database)
                }
            }
        }
    }

    public func upsert(_ schedule: PaneInputSchedule) throws {
        try withDatabase { database in
            let statement = try prepare(
                """
                INSERT INTO pane_input_schedule(
                    schedule_id,
                    surface_id,
                    fire_at,
                    input_text,
                    append_newline
                ) VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(schedule_id) DO UPDATE SET
                    surface_id = excluded.surface_id,
                    fire_at = excluded.fire_at,
                    input_text = excluded.input_text,
                    append_newline = excluded.append_newline
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            try bind(
                schedule.id.rawValue.uuidString,
                at: 1,
                to: statement,
                in: database
            )
            try bind(
                schedule.surfaceID.rawValue.uuidString,
                at: 2,
                to: statement,
                in: database
            )
            guard sqlite3_bind_double(
                statement,
                3,
                schedule.fireAt.timeIntervalSince1970
            ) == SQLITE_OK else {
                throw databaseError(database)
            }
            try bind(schedule.text, at: 4, to: statement, in: database)
            guard sqlite3_bind_int(
                statement,
                5,
                schedule.appendNewline ? 1 : 0
            ) == SQLITE_OK else {
                throw databaseError(database)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database)
            }
        }
    }

    public func delete(id: PaneInputScheduleID) throws {
        try delete(
            sql: "DELETE FROM pane_input_schedule WHERE schedule_id = ?",
            value: id.rawValue.uuidString
        )
    }

    public func deleteAll(for surfaceID: TerminalSurfaceID) throws {
        try delete(
            sql: "DELETE FROM pane_input_schedule WHERE surface_id = ?",
            value: surfaceID.rawValue.uuidString
        )
    }

    public func deleteExpired(atOrBefore date: Date) throws {
        try withDatabase { database in
            let statement = try prepare(
                "DELETE FROM pane_input_schedule WHERE fire_at <= ?",
                in: database
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_double(
                statement,
                1,
                date.timeIntervalSince1970
            ) == SQLITE_OK else {
                throw databaseError(database)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database)
            }
        }
    }

    private func delete(sql: String, value: String) throws {
        try withDatabase { database in
            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            try bind(value, at: 1, to: statement, in: database)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database)
            }
        }
    }

    private func readSchedule(
        from statement: OpaquePointer
    ) throws -> PaneInputSchedule {
        let scheduleID = try readUUID(from: statement, column: 0)
        let surfaceID = try readUUID(from: statement, column: 1)
        guard let textValue = sqlite3_column_text(statement, 3) else {
            throw PaneInputScheduleRepositoryError.missingValue
        }
        return PaneInputSchedule(
            id: PaneInputScheduleID(rawValue: scheduleID),
            surfaceID: TerminalSurfaceID(rawValue: surfaceID),
            fireAt: Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 2)
            ),
            text: String(cString: textValue),
            appendNewline: sqlite3_column_int(statement, 4) != 0
        )
    }

    private func readUUID(
        from statement: OpaquePointer,
        column: Int32
    ) throws -> UUID {
        guard let value = sqlite3_column_text(statement, column) else {
            throw PaneInputScheduleRepositoryError.missingValue
        }
        let identifier = String(cString: value)
        guard let uuid = UUID(uuidString: identifier) else {
            throw PaneInputScheduleRepositoryError.invalidIdentifier(identifier)
        }
        return uuid
    }

    private func withDatabase<T>(
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
            let message = database.map(databaseMessage)
                ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            throw PaneInputScheduleRepositoryError.database(message)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 1_000)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS pane_input_schedule (
                schedule_id TEXT PRIMARY KEY,
                surface_id TEXT NOT NULL,
                fire_at REAL NOT NULL,
                input_text TEXT NOT NULL,
                append_newline INTEGER NOT NULL CHECK(append_newline IN (0, 1))
            ) STRICT
            """,
            in: database
        )
        return try body(database)
    }

    private func execute(
        _ sql: String,
        in database: OpaquePointer
    ) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
    }

    private func prepare(
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

    private func bind(
        _ value: String,
        at index: Int32,
        to statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
        guard result == SQLITE_OK else { throw databaseError(database) }
    }

    private func databaseError(
        _ database: OpaquePointer
    ) -> PaneInputScheduleRepositoryError {
        .database(databaseMessage(database))
    }

    private func databaseMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
