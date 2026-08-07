import Foundation
import MyTTYCore

struct AgentUsageMeterContent: Equatable, Sendable {
    let title: String
    /// What the meter shows, already flipped for `display`.
    let percent: Int
    let display: AgentMeterDisplay
    let isStale: Bool
    /// Whether the meter should be drawn as a warning. Only the agent's
    /// context meter passes a threshold; usage meters leave it nil.
    let isLow: Bool

    init(
        title: String,
        remainingPercent: Double,
        display: AgentMeterDisplay = .remaining,
        isStale: Bool = false,
        lowThresholdPercent: Double? = nil
    ) {
        self.title = title
        let remaining = Int(min(100, max(0, remainingPercent)).rounded())
        self.display = display
        percent = display == .used ? 100 - remaining : remaining
        self.isStale = isStale
        // The threshold is always about remaining context, so the flipped
        // display never moves the warning. Compare the rounded percent so the
        // meter never reads a value that contradicts its own color.
        isLow = lowThresholdPercent.map { Double(remaining) < $0 } ?? false
    }

    var progress: Double {
        Double(percent) / 100
    }

    func tooltip(localizer: MyTTYLocalizer) -> String {
        let base = "\(title) \(percentText(localizer: localizer))"
        guard isStale else { return base }
        return "\(base) · \(localizer.cachedUsageNote())"
    }

    /// Spoken value for the meter. The warning is a color change, so
    /// VoiceOver needs it spelled out.
    func accessibilityValue(localizer: MyTTYLocalizer) -> String {
        let base = percentText(localizer: localizer)
        guard isLow else { return base }
        return "\(base) · \(localizer[.agentContextWarningStatus])"
    }

    private func percentText(localizer: MyTTYLocalizer) -> String {
        switch display {
        case .remaining: localizer.remainingPercent(percent)
        case .used: localizer.usedPercent(percent)
        }
    }
}

struct AgentUsageStatusContent: Equatable, Sendable {
    let costDescription: String?
    let limits: [AgentUsageMeterContent]
    let onDemandUnavailable: Bool
    let planName: String?

    init(
        costDescription: String?,
        limits: [AgentUsageMeterContent],
        onDemandUnavailable: Bool = false,
        planName: String? = nil
    ) {
        self.costDescription = costDescription
        self.limits = limits
        self.onDemandUnavailable = onDemandUnavailable
        self.planName = planName
    }
}

extension AgentUsageSummary {
    func compactDescription(
        localizer: MyTTYLocalizer,
        display: AgentMeterDisplay = .remaining
    ) -> String? {
        guard let content = statusContent(display: display) else { return nil }
        var components = content.costDescription.map { [$0] } ?? []
        components.append(contentsOf: content.limits.map {
            $0.tooltip(localizer: localizer)
        })
        if content.onDemandUnavailable {
            components.append(localizer.onDemandUnavailableNote())
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    func statusContent(
        display: AgentMeterDisplay = .remaining
    ) -> AgentUsageStatusContent? {
        let costDescription = cost.map(Self.describe)
        let visibleLimits = limits.prefix(2).map {
            AgentUsageMeterContent(
                title: $0.title,
                remainingPercent: $0.remainingPercent,
                display: display,
                isStale: limitsAreStale
            )
        }
        guard costDescription != nil
                || !visibleLimits.isEmpty
                || onDemandUnavailable
        else {
            return nil
        }
        return AgentUsageStatusContent(
            costDescription: costDescription,
            limits: visibleLimits,
            onDemandUnavailable: onDemandUnavailable,
            planName: planName
        )
    }

    private static func describe(_ cost: AgentUsageCost) -> String {
        switch cost {
        case let .session(amount, currencyCode):
            currency(amount, code: currencyCode)
        case let .budget(used, limit, currencyCode):
            "\(currency(used, code: currencyCode)) / "
                + currency(limit, code: currencyCode)
        }
    }

    private static func currency(_ amount: Double, code: String) -> String {
        let value = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            amount
        )
        return code.uppercased() == "USD" ? "$\(value)" : "\(code) \(value)"
    }
}

enum AgentUsageStatusSelection {
    static func content(
        activeProvider: AgentProvider?,
        loadedProvider: AgentProvider?,
        summary: AgentUsageSummary?,
        display: AgentMeterDisplay = .remaining
    ) -> AgentUsageStatusContent? {
        guard let activeProvider,
              activeProvider == loadedProvider
        else { return nil }
        return summary?.statusContent(display: display)
    }
}
