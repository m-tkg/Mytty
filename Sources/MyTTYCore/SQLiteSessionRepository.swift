import Foundation
import SQLite3

public enum SessionRepositoryError: Error, Equatable, Sendable {
    case database(String)
    case unsupportedSchemaVersion(Int)
    case emptyPayload
}

public struct SQLiteSessionRepository: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func load() throws -> SessionSnapshot? {
        try withDatabase { database in
            let statement = try prepare(
                """
                SELECT schema_version, payload
                FROM session_snapshot
                WHERE singleton = 1
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return nil
            }
            guard step == SQLITE_ROW else {
                throw databaseError(database)
            }

            let version = Int(sqlite3_column_int(statement, 0))
            guard version == SessionSnapshot.schemaVersion else {
                throw SessionRepositoryError.unsupportedSchemaVersion(version)
            }

            let length = Int(sqlite3_column_bytes(statement, 1))
            guard length > 0,
                  let bytes = sqlite3_column_blob(statement, 1)
            else {
                throw SessionRepositoryError.emptyPayload
            }

            let payload = Data(bytes: bytes, count: length)
            return try JSONDecoder().decode(
                SessionSnapshot.self,
                from: payload
            )
        }
    }

    public func save(_ snapshot: SessionSnapshot) throws {
        let payload = try JSONEncoder().encode(snapshot)

        try withDatabase { database in
            let statement = try prepare(
                """
                INSERT INTO session_snapshot(singleton, schema_version, payload)
                VALUES(1, ?, ?)
                ON CONFLICT(singleton) DO UPDATE SET
                    schema_version = excluded.schema_version,
                    payload = excluded.payload
                """,
                in: database
            )
            defer { sqlite3_finalize(statement) }

            guard sqlite3_bind_int(
                statement,
                1,
                Int32(SessionSnapshot.schemaVersion)
            ) == SQLITE_OK else {
                throw databaseError(database)
            }

            let transient = unsafeBitCast(
                -1,
                to: sqlite3_destructor_type.self
            )
            let bindResult = payload.withUnsafeBytes { bytes in
                sqlite3_bind_blob(
                    statement,
                    2,
                    bytes.baseAddress,
                    Int32(bytes.count),
                    transient
                )
            }
            guard bindResult == SQLITE_OK else {
                throw databaseError(database)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database)
            }
        }
    }

    private func withDatabase<T>(
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        try withConnection { database in
            try execute(
                """
                CREATE TABLE IF NOT EXISTS session_snapshot (
                    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                    schema_version INTEGER NOT NULL,
                    payload BLOB NOT NULL
                ) STRICT
                """,
                in: database
            )

            return try body(database)
        }
    }
}

extension SQLiteSessionRepository: SQLiteRepository {
    static func makeDatabaseError(_ message: String) -> SessionRepositoryError {
        .database(message)
    }
}
