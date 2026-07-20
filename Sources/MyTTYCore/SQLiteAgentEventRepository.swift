import Foundation
import SQLite3

public enum AgentEventRepositoryError: Error, Equatable, Sendable {
    case database(String)
    case emptyPayload
    case invalidIdentifier(String)
}

public struct SQLiteAgentEventRepository: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    @discardableResult
    public func append(_ event: AgentEvent) throws -> Bool {
        let payload = try JSONEncoder().encode(event)

        return try withDatabase { database in
            let statement = try prepare(
                """
                INSERT OR IGNORE INTO agent_event(event_id, payload)
                VALUES(?, ?)
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            try bind(event.id.rawValue.uuidString, at: 1, to: statement, in: database)
            try bind(payload, at: 2, to: statement, in: database)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database)
            }
            return sqlite3_changes(database) == 1
        }
    }

    public func loadEvents() throws -> [AgentEvent] {
        try withDatabase { database in
            let statement = try prepare(
                """
                SELECT payload
                FROM agent_event
                ORDER BY sequence
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            var events: [AgentEvent] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let payload = try readPayload(
                        from: statement,
                        column: 0
                    )
                    events.append(try JSONDecoder().decode(AgentEvent.self, from: payload))
                case SQLITE_DONE:
                    return events
                default:
                    throw databaseError(database)
                }
            }
        }
    }

    @discardableResult
    public func acknowledge(
        eventID: AgentEventID,
        at acknowledgedAt: Date
    ) throws -> Bool {
        try withDatabase { database in
            let statement = try prepare(
                """
                INSERT OR IGNORE INTO attention_acknowledgement(
                    event_id,
                    acknowledged_at
                ) VALUES(?, ?)
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            try bind(eventID.rawValue.uuidString, at: 1, to: statement, in: database)
            guard sqlite3_bind_double(
                statement,
                2,
                acknowledgedAt.timeIntervalSince1970
            ) == SQLITE_OK else {
                throw databaseError(database)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database)
            }
            return sqlite3_changes(database) == 1
        }
    }

    public func loadAcknowledgements() throws -> [AttentionAcknowledgement] {
        try withDatabase { database in
            let statement = try prepare(
                """
                SELECT event_id, acknowledged_at
                FROM attention_acknowledgement
                ORDER BY acknowledged_at, event_id
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            var acknowledgements: [AttentionAcknowledgement] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    guard let eventIDText = sqlite3_column_text(statement, 0)
                    else { throw AgentEventRepositoryError.emptyPayload }
                    let identifier = String(cString: eventIDText)
                    guard let uuid = UUID(uuidString: identifier) else {
                        throw AgentEventRepositoryError.invalidIdentifier(identifier)
                    }
                    acknowledgements.append(
                        AttentionAcknowledgement(
                            eventID: AgentEventID(rawValue: uuid),
                            acknowledgedAt: Date(
                                timeIntervalSince1970: sqlite3_column_double(
                                    statement,
                                    1
                                )
                            )
                        )
                    )
                case SQLITE_DONE:
                    return acknowledgements
                default:
                    throw databaseError(database)
                }
            }
        }
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
            throw AgentEventRepositoryError.database(message)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 1_000)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS agent_event (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT NOT NULL UNIQUE,
                payload BLOB NOT NULL
            ) STRICT
            """,
            in: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS attention_acknowledgement (
                event_id TEXT PRIMARY KEY,
                acknowledged_at REAL NOT NULL
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
        let result = value.withCString { pointer in
            sqlite3_bind_text(
                statement,
                index,
                pointer,
                -1,
                transientDestructor
            )
        }
        guard result == SQLITE_OK else {
            throw databaseError(database)
        }
    }

    private func bind(
        _ value: Data,
        at index: Int32,
        to statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(bytes.count),
                transientDestructor
            )
        }
        guard result == SQLITE_OK else {
            throw databaseError(database)
        }
    }

    private func readPayload(
        from statement: OpaquePointer,
        column: Int32
    ) throws -> Data {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0,
              let bytes = sqlite3_column_blob(statement, column)
        else { throw AgentEventRepositoryError.emptyPayload }
        return Data(bytes: bytes, count: length)
    }

    private var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func databaseError(
        _ database: OpaquePointer
    ) -> AgentEventRepositoryError {
        .database(databaseMessage(database))
    }

    private func databaseMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
