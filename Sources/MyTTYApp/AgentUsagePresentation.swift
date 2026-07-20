import Foundation
import MyTTYCore

struct AgentUsageMeterContent: Equatable, Sendable {
    let title: String
    let percent: Int
    let isStale: Bool

    init(title: String, remainingPercent: Double, isStale: Bool = false) {
        self.title = title
        percent = Int(min(100, max(0, remainingPercent)).rounded())
        self.isStale = isStale
    }

    var progress: Double {
        Double(percent) / 100
    }

    func tooltip(localizer: MyTTYLocalizer) -> String {
        let base = "\(title) \(localizer.remainingPercent(percent))"
        guard isStale else { return base }
        return "\(base) · \(localizer.cachedUsageNote())"
    }
}

struct AgentUsageStatusContent: Equatable, Sendable {
    let costDescription: String?
    let limits: [AgentUsageMeterContent]
}

extension AgentUsageSummary {
    func compactDescription(localizer: MyTTYLocalizer) -> String? {
        guard let content = statusContent() else { return nil }
        var components = content.costDescription.map { [$0] } ?? []
        components.append(contentsOf: content.limits.map {
            $0.tooltip(localizer: localizer)
        })
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    func statusContent() -> AgentUsageStatusContent? {
        let costDescription = cost.map(Self.describe)
        let visibleLimits = limits.prefix(2).map {
            AgentUsageMeterContent(
                title: $0.title,
                remainingPercent: $0.remainingPercent,
                isStale: limitsAreStale
            )
        }
        guard costDescription != nil || !visibleLimits.isEmpty else {
            return nil
        }
        return AgentUsageStatusContent(
            costDescription: costDescription,
            limits: visibleLimits
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
        summary: AgentUsageSummary?
    ) -> AgentUsageStatusContent? {
        guard let activeProvider,
              activeProvider == loadedProvider
        else { return nil }
        return summary?.statusContent()
    }
}
