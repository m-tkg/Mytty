import Foundation
import SQLite3

/// Read-only SQLite access shared by the agent session inspectors.
/// A WAL database whose `-wal` sidecar has been checkpointed away cannot be
/// queried through a plain read-only connection (statements fail with
/// SQLITE_CANTOPEN because the sidecars cannot be created), so reads retry
/// once on an `immutable=1` URI connection. The immutable retry can also
/// fire when a query legitimately finds nothing; that duplicate read is
/// cheap and callers are throttled.
public enum AgentSessionDatabase {
    public static func withReadOnlyConnection<T>(
        at url: URL,
        perform: (OpaquePointer) -> T?
    ) -> T? {
        if let result = withConnection(
            at: url,
            immutable: false,
            perform: perform
        ) {
            return result
        }
        return withConnection(at: url, immutable: true, perform: perform)
    }

    public static func hasTable(
        _ name: String,
        database: OpaquePointer
    ) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func withConnection<T>(
        at url: URL,
        immutable: Bool,
        perform: (OpaquePointer) -> T?
    ) -> T? {
        let path: String
        var flags = SQLITE_OPEN_READONLY
        if immutable {
            guard let encoded = url.path.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) else { return nil }
            path = "file:\(encoded)?immutable=1"
            flags |= SQLITE_OPEN_URI
        } else {
            path = url.path
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        return perform(database)
    }
}
