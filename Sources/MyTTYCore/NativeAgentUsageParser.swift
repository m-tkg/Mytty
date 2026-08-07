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

    public static func cursorSummary(
        from data: Data,
        aggregatedEvents: Data? = nil
    ) throws -> AgentUsageSummary? {
        let response = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        let plan = response.individualUsage?.plan
        let overall = response.individualUsage?.overall
        let pooled = response.teamUsage?.pooled
        let onDemand = response.individualUsage?.onDemand
        let teamOnDemand = response.teamUsage?.onDemand

        let cost = cursorCost(
            onDemand: onDemand,
            teamOnDemand: teamOnDemand
        ) ?? aggregatedEvents.flatMap(cursorAggregatedCost)

        let limits = cursorLimits(plan: plan, overall: overall, pooled: pooled)

        // Plan usage can read 0% used while the account still can't run
        // another request: on a plan with on-demand billing disabled, the
        // plan quota simply refuses further requests once free credits
        // reset, and Cursor's own `enabled: false` flag is the only signal
        // for that — it isn't reflected in `totalPercentUsed`.
        let onDemandUnavailable = plan?.enabled == true && onDemand?.enabled == false
        guard cost != nil || !limits.isEmpty || onDemandUnavailable else { return nil }
        return AgentUsageSummary(
            cost: cost,
            limits: limits,
            onDemandUnavailable: onDemandUnavailable,
            planName: CursorPlanName.resolve(membershipType: response.membershipType)
        )
    }

    /// Personal `plan`/`overall` usage takes precedence over the shared
    /// `teamUsage.pooled` budget: on Enterprise/Team accounts without an
    /// individual cap, the pooled quota is the only meter available, but
    /// it isn't "this user's plan" so it surfaces under a different title.
    private static func cursorLimits(
        plan: CursorPlanUsage?,
        overall: CursorCentsQuota?,
        pooled: CursorCentsQuota?
    ) -> [AgentUsageLimit] {
        let planPercent = plan?.totalPercentUsed ?? {
            guard let used = plan?.used, let limit = plan?.limit, limit > 0
            else { return nil }
            return used / limit * 100
        }()
        let overallPercent: Double? = if overall?.enabled != false,
                                        let used = overall?.used,
                                        let limit = overall?.limit,
                                        limit > 0 {
            used / limit * 100
        } else {
            nil
        }
        let pooledPercent: Double? = if pooled?.enabled != false,
                                       let used = pooled?.used,
                                       let limit = pooled?.limit,
                                       limit > 0 {
            used / limit * 100
        } else {
            nil
        }
        let primary: (title: String, usedPercent: Double)? =
            if let planPercent { ("Plan", planPercent) }
            else if let overallPercent { ("Plan", overallPercent) }
            else if let pooledPercent { ("Team", pooledPercent) }
            else { nil }

        return [
            primary,
            plan?.autoPercentUsed.map { ("Auto", $0) },
            plan?.apiPercentUsed.map { ("API", $0) },
        ].compactMap { value -> AgentUsageLimit? in
            guard let (title, usedPercent) = value else { return nil }
            return AgentUsageLimit(
                title: title,
                remainingPercent: 100 - usedPercent
            )
        }
    }

    /// A personal on-demand budget wins over the shared team-pool budget,
    /// and any budget wins over a bare session amount: on Enterprise/Team
    /// accounts the personal on-demand cap is often `limit: null`, in which
    /// case the team pool's budget is the real, more informative meter and
    /// should be preferred over falling back to a plain session amount.
    private static func cursorCost(
        onDemand: CursorOnDemandUsage?,
        teamOnDemand: CursorOnDemandUsage?
    ) -> AgentUsageCost? {
        cursorOnDemandBudget(onDemand)
            ?? cursorOnDemandBudget(teamOnDemand)
            ?? cursorOnDemandSession(onDemand)
            ?? cursorOnDemandSession(teamOnDemand)
    }

    private static func cursorOnDemandBudget(
        _ onDemand: CursorOnDemandUsage?
    ) -> AgentUsageCost? {
        guard onDemand?.enabled != false,
              let used = onDemand?.used,
              let limit = onDemand?.limit,
              limit > 0
        else { return nil }
        return .budget(used: used / 100, limit: limit / 100, currencyCode: "USD")
    }

    private static func cursorOnDemandSession(
        _ onDemand: CursorOnDemandUsage?
    ) -> AgentUsageCost? {
        guard onDemand?.enabled != false,
              let used = onDemand?.used,
              used > 0
        else { return nil }
        return .session(amount: used / 100, currencyCode: "USD")
    }

    /// Parses the ISO8601 `billingCycleStart`/`billingCycleEnd` timestamps out
    /// of a Cursor usage-summary payload and returns them as epoch-ms, for use
    /// as the `startDate`/`endDate` window on the aggregated-usage-events
    /// request. Returns `nil` if either field is missing or unparseable.
    public static func cursorBillingCycle(
        from data: Data
    ) -> (startMs: Int64, endMs: Int64)? {
        guard let response = try? JSONDecoder().decode(
            CursorUsageResponse.self,
            from: data
        ),
              let start = response.billingCycleStart,
              let end = response.billingCycleEnd,
              let startDate = parseCursorDate(start),
              let endDate = parseCursorDate(end)
        else { return nil }
        return (
            startMs: Int64((startDate.timeIntervalSince1970 * 1_000).rounded()),
            endMs: Int64((endDate.timeIntervalSince1970 * 1_000).rounded())
        )
    }

    private static func parseCursorDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Parses the aggregated-usage-events payload into a session cost.
    /// Malformed or missing data yields `nil` rather than throwing, so a
    /// failure here never discards the surrounding usage summary.
    private static func cursorAggregatedCost(from data: Data) -> AgentUsageCost? {
        guard let response = try? JSONDecoder().decode(
            CursorAggregatedEventsResponse.self,
            from: data
        ),
              let totalCostCents = response.totalCostCents,
              totalCostCents.isFinite,
              totalCostCents > 0,
              totalCostCents <= 100_000_000
        else { return nil }
        return .session(amount: totalCostCents / 100, currencyCode: "USD")
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
    let teamUsage: CursorTeamUsage?
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
}

private struct CursorAggregatedEventsResponse: Decodable {
    let totalCostCents: Double?
}

private struct CursorIndividualUsage: Decodable {
    let plan: CursorPlanUsage?
    let onDemand: CursorOnDemandUsage?
    let overall: CursorCentsQuota?
}

private struct CursorTeamUsage: Decodable {
    let onDemand: CursorOnDemandUsage?
    let pooled: CursorCentsQuota?
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

/// Shared shape for `individualUsage.overall` and `teamUsage.pooled`: a
/// cents-denominated quota with the same `enabled`/`used`/`limit` fields as
/// on-demand usage, but representing a capacity meter rather than spend.
private struct CursorCentsQuota: Decodable {
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
