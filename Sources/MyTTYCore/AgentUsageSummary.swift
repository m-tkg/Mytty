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
    /// True when the provider reports its plan quota as unused while also
    /// signaling that on-demand billing is unavailable — the plan meters
    /// alone would read as "plenty left" even though no more usage is
    /// actually possible.
    public let onDemandUnavailable: Bool

    public init(
        cost: AgentUsageCost?,
        limits: [AgentUsageLimit],
        limitsAreStale: Bool = false,
        onDemandUnavailable: Bool = false
    ) {
        self.cost = cost
        self.limits = limits
        self.limitsAreStale = limitsAreStale
        self.onDemandUnavailable = onDemandUnavailable
    }
}
