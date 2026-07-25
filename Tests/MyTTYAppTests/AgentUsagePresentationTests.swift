import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Agent usage presentation")
struct AgentUsagePresentationTests {
    @Test("formats compact agent cost and limits")
    func agentUsagePresentation() throws {
        let summary = AgentUsageSummary(
            cost: .session(amount: 0.421, currencyCode: "USD"),
            limits: [
                AgentUsageLimit(title: "5h", remainingPercent: 72.6),
                AgentUsageLimit(title: "7d", remainingPercent: 48.2),
                AgentUsageLimit(title: "Other", remainingPercent: 99),
            ]
        )

        #expect(
            summary.compactDescription(
                localizer: MyTTYLocalizer(language: .english)
            ) == "$0.42 · 5h 73% left · 7d 48% left"
        )
        #expect(
            summary.compactDescription(
                localizer: MyTTYLocalizer(language: .japanese)
            ) == "$0.42 · 5h 残り73% · 7d 残り48%"
        )

        let statusContent = try #require(summary.statusContent())
        #expect(statusContent.costDescription == "$0.42")
        #expect(statusContent.limits.map(\.title) == ["5h", "7d"])
        #expect(statusContent.limits.map(\.percent) == [73, 48])
        #expect(statusContent.limits.map(\.progress) == [0.73, 0.48])
        #expect(statusContent.limits.map(\.isStale) == [false, false])

        let staleSummary = AgentUsageSummary(
            cost: .session(amount: 0.421, currencyCode: "USD"),
            limits: [AgentUsageLimit(title: "5h", remainingPercent: 72.6)],
            limitsAreStale: true
        )
        let staleContent = try #require(staleSummary.statusContent())
        #expect(staleContent.limits.map(\.isStale) == [true])
        #expect(
            staleContent.limits[0].tooltip(
                localizer: MyTTYLocalizer(language: .english)
            ) == "5h 73% left · cached"
        )
        #expect(
            staleContent.limits[0].tooltip(
                localizer: MyTTYLocalizer(language: .japanese)
            ) == "5h 残り73% · キャッシュ"
        )

        let overLimit = AgentUsageMeterContent(
            title: "Plan",
            remainingPercent: 140
        )
        let underLimit = AgentUsageMeterContent(
            title: "Plan",
            remainingPercent: -20
        )
        #expect(overLimit.percent == 100)
        #expect(overLimit.progress == 1)
        #expect(underLimit.percent == 0)
        #expect(underLimit.progress == 0)

        let budget = AgentUsageSummary(
            cost: .budget(
                used: 12.3,
                limit: 50,
                currencyCode: "USD"
            ),
            limits: []
        )
        #expect(
            budget.compactDescription(
                localizer: MyTTYLocalizer(language: .english)
            ) == "$12.30 / $50.00"
        )
    }

    @Test("flags a meter as low only below the warning threshold")
    func lowContextFlag() throws {
        func meter(
            _ remaining: Double,
            threshold: Double? = 30
        ) -> AgentUsageMeterContent {
            AgentUsageMeterContent(
                title: "Context",
                remainingPercent: remaining,
                lowThresholdPercent: threshold
            )
        }

        #expect(meter(12).isLow)
        // The comparison uses the rounded percent the meter displays, so a
        // meter reading 30% is never flagged even when the raw value is
        // slightly under the threshold.
        #expect(!meter(29.6).isLow)
        #expect(meter(29.4).isLow)
        #expect(!meter(30).isLow)
        #expect(!meter(64).isLow)

        // Usage meters and a disabled warning pass no threshold at all.
        #expect(!meter(4, threshold: nil).isLow)
        #expect(
            !AgentUsageMeterContent(
                title: "5h",
                remainingPercent: 2
            ).isLow
        )

        let summary = AgentUsageSummary(
            cost: nil,
            limits: [AgentUsageLimit(title: "5h", remainingPercent: 3)]
        )
        #expect(summary.statusContent()?.limits.first?.isLow == false)
    }

    @Test("spells out the low context warning for VoiceOver")
    func lowContextAccessibilityValue() throws {
        let low = AgentUsageMeterContent(
            title: "Context",
            remainingPercent: 12,
            lowThresholdPercent: 30
        )
        let normal = AgentUsageMeterContent(
            title: "Context",
            remainingPercent: 64,
            lowThresholdPercent: 30
        )

        #expect(
            low.accessibilityValue(
                localizer: MyTTYLocalizer(language: .english)
            ) == "12% left · Running low"
        )
        #expect(
            low.accessibilityValue(
                localizer: MyTTYLocalizer(language: .japanese)
            ) == "残り12% · 残量わずか"
        )
        #expect(
            normal.accessibilityValue(
                localizer: MyTTYLocalizer(language: .english)
            ) == "64% left"
        )
    }
}
