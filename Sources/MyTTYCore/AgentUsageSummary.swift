import Foundation

public struct AgentUsageLimit: Codable, Equatable, Sendable {
    public let title: String
    public let remainingPercent: Double

    public init(title: String, remainingPercent: Double) {
        self.title = title
        self.remainingPercent = remainingPercent
    }
}

public enum AgentUsageCost: Equatable, Sendable {
    case session(amount: Double, currencyCode: String)
    case budget(used: Double, limit: Double, currencyCode: String)
}

public struct AgentUsageSummary: Equatable, Sendable {
    public let cost: AgentUsageCost?
    public let limits: [AgentUsageLimit]
    public let limitsAreStale: Bool

    public init(
        cost: AgentUsageCost?,
        limits: [AgentUsageLimit],
        limitsAreStale: Bool = false
    ) {
        self.cost = cost
        self.limits = limits
        self.limitsAreStale = limitsAreStale
    }
}
