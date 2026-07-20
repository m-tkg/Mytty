import Foundation
import SQLite3

public enum OpenCodeUsageProbe {
    private static let fiveHours: TimeInterval = 5 * 60 * 60
    private static let limits = (
        fiveHours: 12.0,
        weekly: 30.0,
        monthly: 60.0
    )

    private struct UsageRow: Sendable {
        let createdAt: Date
        let cost: Double
    }

    public static func fetch(
        homeDirectory: URL,
        now: Date = Date()
    ) async -> AgentUsageSummary? {
        await Task.detached(priority: .utility) {
            fetchSynchronously(homeDirectory: homeDirectory, now: now)
        }.value
    }

    private static func fetchSynchronously(
        homeDirectory: URL,
        now: Date
    ) -> AgentUsageSummary? {
        let directory = homeDirectory
            .appending(path: ".local/share/opencode", directoryHint: .isDirectory)
        guard hasOpenCodeGoAuth(
            at: directory.appending(path: "auth.json")
        ),
              let rows = usageRows(
                  databaseURL: directory.appending(path: "opencode.db")
              )
        else { return nil }

        let fiveHourStart = now.addingTimeInterval(-fiveHours)
        let weekStart = startOfUTCWeek(now)
        let monthStart = startOfUTCMonth(now)
        let fiveHourCost = sum(rows, from: fiveHourStart, to: now)
        let weeklyCost = sum(rows, from: weekStart, to: now)
        let monthlyCost = sum(rows, from: monthStart, to: now)
        return AgentUsageSummary(
            cost: nil,
            limits: [
                AgentUsageLimit(
                    title: "5h",
                    remainingPercent: remaining(
                        used: fiveHourCost,
                        limit: limits.fiveHours
                    )
                ),
                AgentUsageLimit(
                    title: "7d",
                    remainingPercent: remaining(
                        used: weeklyCost,
                        limit: limits.weekly
                    )
                ),
                AgentUsageLimit(
                    title: "Monthly",
                    remainingPercent: remaining(
                        used: monthlyCost,
                        limit: limits.monthly
                    )
                ),
            ]
        )
    }

    private static func hasOpenCodeGoAuth(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let entry = object["opencode-go"] as? [String: Any],
              let key = entry["key"] as? String
        else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func usageRows(databaseURL: URL) -> [UsageRow]? {
        AgentSessionDatabase.withReadOnlyConnection(at: databaseURL) { database in
            guard AgentSessionDatabase.hasTable("message", database: database)
            else { return nil }
            let query = AgentSessionDatabase.hasTable("part", database: database)
                ? messageAndPartUsageQuery
                : messageUsageQuery
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil)
                    == SQLITE_OK
            else { return nil }
            defer { sqlite3_finalize(statement) }

            var rows: [UsageRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let createdMilliseconds = sqlite3_column_int64(statement, 0)
                let cost = sqlite3_column_double(statement, 1)
                guard createdMilliseconds > 0,
                      cost >= 0,
                      cost.isFinite
                else { continue }
                rows.append(UsageRow(
                    createdAt: Date(
                        timeIntervalSince1970: Double(createdMilliseconds) / 1_000
                    ),
                    cost: cost
                ))
            }
            return rows
        }
    }

    private static func sum(
        _ rows: [UsageRow],
        from start: Date,
        to end: Date
    ) -> Double {
        rows.reduce(0) { total, row in
            guard row.createdAt >= start, row.createdAt <= end else {
                return total
            }
            return total + row.cost
        }
    }

    private static func remaining(used: Double, limit: Double) -> Double {
        min(100, max(0, (1 - used / limit) * 100))
    }

    private static func startOfUTCWeek(_ date: Date) -> Date {
        var calendar = utcCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let components = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: date
        )
        return calendar.date(from: components) ?? date
    }

    private static func startOfUTCMonth(_ date: Date) -> Date {
        let calendar = utcCalendar
        return calendar.date(from: calendar.dateComponents(
            [.year, .month],
            from: date
        )) ?? date
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static let messageUsageQuery = """
        SELECT
          CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER),
          CAST(json_extract(data, '$.cost') AS REAL)
        FROM message
        WHERE json_valid(data)
          AND json_extract(data, '$.providerID') = 'opencode-go'
          AND json_extract(data, '$.role') = 'assistant'
          AND json_type(data, '$.cost') IN ('integer', 'real');
        """

    private static let messageAndPartUsageQuery = """
        WITH message_costs AS (
          SELECT
            id AS messageID,
            CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
            CAST(json_extract(data, '$.cost') AS REAL) AS cost
          FROM message
          WHERE json_valid(data)
            AND json_extract(data, '$.providerID') = 'opencode-go'
            AND json_extract(data, '$.role') = 'assistant'
            AND json_type(data, '$.cost') IN ('integer', 'real')
        )
        SELECT createdMs, cost FROM message_costs
        UNION ALL
        SELECT
          CAST(COALESCE(json_extract(p.data, '$.time.created'), p.time_created, m.time_created) AS INTEGER),
          CAST(json_extract(p.data, '$.cost') AS REAL)
        FROM part p
        JOIN message m ON m.id = p.message_id
        WHERE json_valid(p.data)
          AND json_valid(m.data)
          AND json_extract(p.data, '$.type') = 'step-finish'
          AND json_type(p.data, '$.cost') IN ('integer', 'real')
          AND json_extract(m.data, '$.providerID') = 'opencode-go'
          AND json_extract(m.data, '$.role') = 'assistant'
          AND NOT EXISTS (
            SELECT 1 FROM message_costs
            WHERE message_costs.messageID = p.message_id
          );
        """
}
