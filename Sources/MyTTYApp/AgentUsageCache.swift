import Foundation
import MyTTYCore

protocol AgentUsageLoading: Sendable {
    func loadSummary(for provider: AgentProvider) async -> AgentUsageSummary?
}

actor AgentUsageCache {
    private struct Entry: Sendable {
        let summary: AgentUsageSummary?
        let loadedAt: Date
    }

    private let loader: any AgentUsageLoading
    private let lifetime: TimeInterval
    private let missingLifetime: TimeInterval
    private let claudeLifetime: TimeInterval
    private var entries: [AgentProvider: Entry] = [:]

    init(
        loader: any AgentUsageLoading,
        lifetime: TimeInterval = 60,
        missingLifetime: TimeInterval = 2,
        claudeLifetime: TimeInterval = 5 * 60
    ) {
        self.loader = loader
        self.lifetime = max(0, lifetime)
        self.missingLifetime = max(0, missingLifetime)
        self.claudeLifetime = max(0, claudeLifetime)
    }

    func summary(
        for provider: AgentProvider,
        now: Date = Date()
    ) async -> AgentUsageSummary? {
        if let entry = entries[provider] {
            let validFor = cacheLifetime(
                for: provider,
                summary: entry.summary
            )
            if now.timeIntervalSince(entry.loadedAt) < validFor {
                return entry.summary
            }
        }

        let summary = await loader.loadSummary(for: provider)
        entries[provider] = Entry(summary: summary, loadedAt: now)
        return summary
    }

    private func cacheLifetime(
        for provider: AgentProvider,
        summary: AgentUsageSummary?
    ) -> TimeInterval {
        let defaultLifetime = summary == nil ? missingLifetime : lifetime
        guard provider == .claudeCode else { return defaultLifetime }
        return max(defaultLifetime, claudeLifetime)
    }
}
