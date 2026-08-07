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
    /// The account's subscription plan (e.g. "Pro", "Max 20x"), normalized
    /// by `AgentPlanName` for the provider that produced this summary.
    /// `nil` when the provider's payload carried no recognizable plan.
    public let planName: String?

    public init(
        cost: AgentUsageCost?,
        limits: [AgentUsageLimit],
        limitsAreStale: Bool = false,
        onDemandUnavailable: Bool = false,
        planName: String? = nil
    ) {
        self.cost = cost
        self.limits = limits
        self.limitsAreStale = limitsAreStale
        self.onDemandUnavailable = onDemandUnavailable
        self.planName = planName
    }

    /// The plan is resolved from the provider's credentials rather than
    /// from the usage payload, so every loader derives it separately and
    /// stamps it onto whichever summary it ended up with.
    public func withPlanName(_ planName: String?) -> AgentUsageSummary {
        AgentUsageSummary(
            cost: cost,
            limits: limits,
            limitsAreStale: limitsAreStale,
            onDemandUnavailable: onDemandUnavailable,
            planName: planName
        )
    }
}
