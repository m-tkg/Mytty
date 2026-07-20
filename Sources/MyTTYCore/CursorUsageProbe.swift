import Foundation
import SQLite3

public enum CursorUsageProbe {
    public static func fetch(homeDirectory: URL) async -> Data? {
        let token = await Task.detached(priority: .utility) {
            CursorCredentialStore.accessToken(homeDirectory: homeDirectory)
        }.value
        guard let token,
              let cookie = try? CursorCredentialStore.cookieHeader(
                  accessToken: token
              ),
              let url = URL(string: "https://cursor.com/api/usage-summary")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? NativeAgentUsageParser.cursorSummary(from: data)) != nil
        else { return nil }
        return data
    }
}

enum CursorCredentialStore {
    enum CredentialError: Error {
        case invalidToken
        case expiredToken
    }

    static func accessToken(homeDirectory: URL) -> String? {
        let databaseURL = homeDirectory
            .appending(path: "Library/Application Support/Cursor/User/globalStorage")
            .appending(path: "state.vscdb")
        return AgentSessionDatabase.withReadOnlyConnection(
            at: databaseURL
        ) { database in
            let query = "SELECT value FROM ItemTable "
                + "WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil)
                    == SQLITE_OK
            else { return nil }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            switch sqlite3_column_type(statement, 0) {
            case SQLITE_TEXT:
                guard let value = sqlite3_column_text(statement, 0) else {
                    return nil
                }
                return String(cString: value)
            case SQLITE_BLOB:
                guard let bytes = sqlite3_column_blob(statement, 0) else {
                    return nil
                }
                let data = Data(
                    bytes: bytes,
                    count: Int(sqlite3_column_bytes(statement, 0))
                )
                return String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16LittleEndian)
            default:
                return nil
            }
        }
    }

    static func cookieHeader(
        accessToken: String,
        now: Date = Date()
    ) throws -> String {
        let parts = accessToken.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard parts.count >= 2 else { throw CredentialError.invalidToken }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let subject = object["sub"] as? String,
              let userID = subject.split(separator: "|").last.map(String.init),
              !userID.isEmpty,
              let expiration = object["exp"] as? NSNumber
        else { throw CredentialError.invalidToken }
        guard expiration.doubleValue > now.addingTimeInterval(60)
            .timeIntervalSince1970
        else { throw CredentialError.expiredToken }

        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))
        guard userID.unicodeScalars.allSatisfy(allowed.contains) else {
            throw CredentialError.invalidToken
        }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }
}
