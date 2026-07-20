import Foundation

public enum NativeAgentUsageParser {
    static func limitTitle(windowMinutes: Int?, fallback: String) -> String {
        guard let minutes = windowMinutes, minutes > 0 else { return fallback }
        if minutes.isMultiple(of: 24 * 60) {
            return "\(minutes / (24 * 60))d"
        }
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    public static func codexSummary(
        from data: Data,
        sessionCostUSD: Double?
    ) throws -> AgentUsageSummary? {
        let response = try JSONDecoder().decode(CodexResponse.self, from: data)
        let rateLimits = response.rateLimits
        let cost: AgentUsageCost? = if let budget = rateLimits.individualLimit,
                                      let used = budget.used,
                                      let limit = budget.limit,
                                      limit > 0 {
            .budget(used: used, limit: limit, currencyCode: "USD")
        } else if let sessionCostUSD {
            .session(amount: sessionCostUSD, currencyCode: "USD")
        } else {
            nil
        }
        let limits = [rateLimits.primary, rateLimits.secondary]
            .compactMap { window -> AgentUsageLimit? in
                guard let window else { return nil }
                return AgentUsageLimit(
                    title: limitTitle(
                        windowMinutes: window.windowDurationMins,
                        fallback: "Limit"
                    ),
                    remainingPercent: 100 - window.usedPercent
                )
            }
        guard cost != nil || !limits.isEmpty else { return nil }
        return AgentUsageSummary(cost: cost, limits: limits)
    }

    public static func claudeSummary(
        from data: Data,
        sessionCostUSD: Double?
    ) throws -> AgentUsageSummary? {
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let cost = sessionCostUSD.map {
            AgentUsageCost.session(amount: $0, currencyCode: "USD")
        }
        let weekly = claudeLimit(title: "7d", window: response.sevenDay)
            ?? claudeLimit(
                title: "7d",
                window: response.sevenDayOAuthApps
            )
        let windowLimits = [
            claudeLimit(title: "5h", window: response.fiveHour),
            weekly,
            claudeLimit(title: "Sonnet", window: response.sevenDaySonnet),
            claudeLimit(title: "Opus", window: response.sevenDayOpus),
        ].compactMap { $0 }
        let scopedLimits = (response.limits ?? []).compactMap {
            entry -> AgentUsageLimit? in
            guard let usedPercent = entry.percent else { return nil }
            let name = entry.scope?.model?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Weekly"
            return AgentUsageLimit(
                title: title,
                remainingPercent: 100 - usedPercent
            )
        }
        var seenTitles: Set<String> = []
        let limits = (windowLimits + scopedLimits).filter {
            seenTitles.insert($0.title).inserted
        }
        guard cost != nil || !limits.isEmpty else { return nil }
        return AgentUsageSummary(cost: cost, limits: limits)
    }

    public static func antigravitySummary(from data: Data) throws -> AgentUsageSummary? {
        let response = try JSONDecoder().decode(
            AntigravityResponse.self,
            from: data
        )
        let groups = response.response?.groups
            ?? response.summary?.groups
            ?? response.groups
            ?? []
        let limits = groups.compactMap { group -> (Int, AgentUsageLimit)? in
            let available = (group.buckets ?? []).compactMap { bucket -> Double? in
                guard bucket.disabled != true else { return nil }
                return bucket.remainingFraction
                    ?? bucket.remaining?.resolvedFraction
            }
            guard let remaining = available.min() else { return nil }
            let normalized = group.displayName.lowercased()
            let title: String
            let rank: Int
            if normalized.contains("gemini") {
                title = "Gemini"
                rank = 0
            } else if normalized.contains("claude")
                        || normalized.contains("gpt") {
                title = "Claude/GPT"
                rank = 1
            } else {
                title = group.displayName
                rank = 2
            }
            return (
                rank,
                AgentUsageLimit(
                    title: title,
                    remainingPercent: min(1, max(0, remaining)) * 100
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1.title < rhs.1.title
        }
        .map(\.1)
        guard !limits.isEmpty else { return nil }
        return AgentUsageSummary(cost: nil, limits: limits)
    }

    public static func cursorSummary(from data: Data) throws -> AgentUsageSummary? {
        let response = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        let plan = response.individualUsage?.plan
        let onDemand = response.individualUsage?.onDemand
        let cost: AgentUsageCost? = if onDemand?.enabled != false,
                                      let used = onDemand?.used {
            if let limit = onDemand?.limit, limit > 0 {
                .budget(
                    used: used / 100,
                    limit: limit / 100,
                    currencyCode: "USD"
                )
            } else if used > 0 {
                .session(amount: used / 100, currencyCode: "USD")
            } else {
                nil
            }
        } else {
            nil
        }
        let totalPercent = plan?.totalPercentUsed ?? {
            guard let used = plan?.used,
                  let limit = plan?.limit,
                  limit > 0
            else { return nil }
            return used / limit * 100
        }()
        let limits = [
            totalPercent.map { ("Plan", $0) },
            plan?.autoPercentUsed.map { ("Auto", $0) },
            plan?.apiPercentUsed.map { ("API", $0) },
        ].compactMap { value -> AgentUsageLimit? in
            guard let (title, usedPercent) = value else { return nil }
            return AgentUsageLimit(
                title: title,
                remainingPercent: 100 - usedPercent
            )
        }
        guard cost != nil || !limits.isEmpty else { return nil }
        return AgentUsageSummary(cost: cost, limits: limits)
    }

    public static func costOnly(_ sessionCostUSD: Double?) -> AgentUsageSummary? {
        guard let sessionCostUSD else { return nil }
        return AgentUsageSummary(
            cost: .session(amount: sessionCostUSD, currencyCode: "USD"),
            limits: []
        )
    }

    private static func claudeLimit(
        title: String,
        window: ClaudeUsageWindow?
    ) -> AgentUsageLimit? {
        guard let utilization = window?.utilization else { return nil }
        return AgentUsageLimit(
            title: title,
            remainingPercent: 100 - utilization
        )
    }
}

private struct CodexResponse: Decodable {
    let rateLimits: CodexRateLimits
}

private struct CodexRateLimits: Decodable {
    let primary: CodexRateWindow?
    let secondary: CodexRateWindow?
    let individualLimit: CodexBudget?
}

private struct CodexRateWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
}

private struct CodexBudget: Decodable {
    let limit: Double?
    let used: Double?
}

private struct ClaudeResponse: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?
    let sevenDayOAuthApps: ClaudeUsageWindow?
    let sevenDayOpus: ClaudeUsageWindow?
    let sevenDaySonnet: ClaudeUsageWindow?
    let limits: [ClaudeUsageLimitEntry]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
    }
}

private struct ClaudeUsageWindow: Decodable {
    let utilization: Double?
}

private struct ClaudeUsageLimitEntry: Decodable {
    let percent: Double?
    let scope: ClaudeUsageLimitScope?
}

private struct ClaudeUsageLimitScope: Decodable {
    let model: ClaudeUsageLimitModel?
}

private struct ClaudeUsageLimitModel: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct CursorUsageResponse: Decodable {
    let individualUsage: CursorIndividualUsage?
}

private struct CursorIndividualUsage: Decodable {
    let plan: CursorPlanUsage?
    let onDemand: CursorOnDemandUsage?
}

private struct CursorPlanUsage: Decodable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

private struct CursorOnDemandUsage: Decodable {
    let enabled: Bool?
    let used: Double?
    let limit: Double?
}

private struct AntigravityResponse: Decodable {
    let response: AntigravityPayload?
    let summary: AntigravityPayload?
    let groups: [AntigravityGroup]?
}

private struct AntigravityPayload: Decodable {
    let groups: [AntigravityGroup]
}

private struct AntigravityGroup: Decodable {
    let displayName: String
    let buckets: [AntigravityBucket]?
}

private struct AntigravityBucket: Decodable {
    let disabled: Bool?
    let remainingFraction: Double?
    let remaining: AntigravityRemaining?
}

private struct AntigravityRemaining: Decodable {
    let oneOfCase: String?
    let value: Double?
    let remainingFraction: Double?

    enum CodingKeys: String, CodingKey {
        case oneOfCase = "case"
        case value
        case remainingFraction
    }

    var resolvedFraction: Double? {
        if oneOfCase == nil || oneOfCase == "remainingFraction" {
            return remainingFraction ?? value
        }
        return nil
    }
}
