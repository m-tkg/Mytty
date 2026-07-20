import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// Characterization tests for `AgentUsagePollingCoordinator`: pin down the
/// behavior extracted from `TerminalWindowController.refreshAgentUsageIfNeeded`
/// — only refetching when the focused pane's provider changes (or `force`
/// is set), discarding a load whose provider is no longer focused by the
/// time it completes, and clearing state once no provider is focused.
///
/// A `GatedUsageLoader` stands in for `NativeAgentUsageLoader` so tests can
/// suspend a load mid-flight (per provider) and control exactly when it
/// resolves, to exercise the request-superseding race without depending on
/// wall-clock timing.
@Suite("Agent usage polling coordinator")
struct AgentUsagePollingCoordinatorTests {
    private func summary(_ tag: String) -> AgentUsageSummary {
        AgentUsageSummary(
            cost: .session(amount: 1, currencyCode: "USD"),
            limits: [AgentUsageLimit(title: tag, remainingPercent: 50)]
        )
    }

    /// Task scheduling on the MainActor executor is cooperative, so after
    /// starting a load, tests need to wait for the loader's actor hop and
    /// the continuation back onto the MainActor to actually run. Polls
    /// `condition` instead of sleeping a fixed duration so the tests stay
    /// reliable when the suite runs under load (parallel test execution
    /// competing for the same MainActor).
    @MainActor
    private func settle(
        until condition: () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// For assertions about the *absence* of an async effect, where there's
    /// no condition to poll for — just a bounded wait to give any
    /// unexpected work a chance to run before asserting nothing changed.
    @MainActor
    private func pause() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("loads usage for the focused pane's provider")
    @MainActor
    func loadsUsageForProvider() async {
        let loader = GatedUsageLoader()
        await loader.setResult(.codex, summary("codex"))
        var changeCount = 0
        let coordinator = AgentUsagePollingCoordinator(
            cache: AgentUsageCache(loader: loader, lifetime: 0, missingLifetime: 0, claudeLifetime: 0),
            foregroundProvider: { .codex },
            onUsageChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded()
        await settle { coordinator.loadedProvider != nil }

        #expect(coordinator.loadedProvider == .codex)
        #expect(coordinator.loadedSummary == summary("codex"))
        #expect(changeCount == 1)
        #expect(await loader.loadCount(for: .codex) == 1)
    }

    @Test("does nothing when no pane has a focused provider")
    @MainActor
    func noProviderDoesNothing() async {
        let loader = GatedUsageLoader()
        var changeCount = 0
        let coordinator = AgentUsagePollingCoordinator(
            cache: AgentUsageCache(loader: loader, lifetime: 0, missingLifetime: 0, claudeLifetime: 0),
            foregroundProvider: { nil },
            onUsageChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded()
        await pause()

        #expect(coordinator.loadedProvider == nil)
        #expect(coordinator.loadedSummary == nil)
        #expect(changeCount == 0)
    }

    @Test("skips refetching the same provider without force")
    @MainActor
    func sameProviderSkipsWithoutForce() async {
        let loader = GatedUsageLoader()
        await loader.setResult(.codex, summary("codex"))
        let coordinator = AgentUsagePollingCoordinator(
            cache: AgentUsageCache(loader: loader, lifetime: 0, missingLifetime: 0, claudeLifetime: 0),
            foregroundProvider: { .codex },
            onUsageChanged: {}
        )

        coordinator.refreshIfNeeded()
        await settle { coordinator.loadedProvider != nil }
        coordinator.refreshIfNeeded()
        await pause()

        #expect(await loader.loadCount(for: .codex) == 1)
    }

    @Test("force refetches the same provider")
    @MainActor
    func forceRefetchesSameProvider() async {
        let loader = GatedUsageLoader()
        await loader.setResult(.codex, summary("codex"))
        let coordinator = AgentUsagePollingCoordinator(
            cache: AgentUsageCache(loader: loader, lifetime: 0, missingLifetime: 0, claudeLifetime: 0),
            foregroundProvider: { .codex },
            onUsageChanged: {}
        )

        coordinator.refreshIfNeeded()
        await settle { coordinator.loadedProvider != nil }
        coordinator.refreshIfNeeded(force: true)
        await settle { await loader.loadCount(for: .codex) == 2 }

        #expect(await loader.loadCount(for: .codex) == 2)
    }

    @Test("discards a stale load once a different provider becomes focused")
    @MainActor
    func discardsStaleLoadOnProviderChange() async {
        let loader = GatedUsageLoader()
        await loader.setResult(.codex, summary("codex"))
        await loader.setResult(.claudeCode, summary("claude"))
        await loader.hold(.codex)
        var focused: AgentProvider? = .codex
        var changeCount = 0
        let coordinator = AgentUsagePollingCoordinator(
            cache: AgentUsageCache(loader: loader, lifetime: 0, missingLifetime: 0, claudeLifetime: 0),
            foregroundProvider: { focused },
            onUsageChanged: { changeCount += 1 }
        )

        // Starts a load for .codex that suspends inside the loader; wait
        // for the loader to actually observe the call before proceeding,
        // otherwise the "focus moves" step below might race ahead of it.
        coordinator.refreshIfNeeded()
        await settle { await loader.loadCount(for: .codex) > 0 }
        #expect(coordinator.loadedProvider == nil)

        // Focus moves to Claude Code before the Codex load resolves; this
        // cancels the in-flight Codex task and starts a fresh one.
        focused = .claudeCode
        coordinator.refreshIfNeeded()
        await settle { coordinator.loadedProvider != nil }

        #expect(coordinator.loadedProvider == .claudeCode)
        #expect(coordinator.loadedSummary == summary("claude"))
        #expect(changeCount == 1)

        // Releasing the stale Codex load must not overwrite the result
        // that's already showing for Claude Code.
        await loader.release(.codex)
        await pause()

        #expect(coordinator.loadedProvider == .claudeCode)
        #expect(coordinator.loadedSummary == summary("claude"))
        #expect(changeCount == 1)
    }

    @Test("losing focus cancels the in-flight load and clears the request")
    @MainActor
    func losingFocusCancelsInFlightLoad() async {
        let loader = GatedUsageLoader()
        await loader.setResult(.codex, summary("codex"))
        await loader.hold(.codex)
        var focused: AgentProvider? = .codex
        var changeCount = 0
        let coordinator = AgentUsagePollingCoordinator(
            cache: AgentUsageCache(loader: loader, lifetime: 0, missingLifetime: 0, claudeLifetime: 0),
            foregroundProvider: { focused },
            onUsageChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded()
        await settle { await loader.loadCount(for: .codex) > 0 }

        focused = nil
        coordinator.refreshIfNeeded()
        await loader.release(.codex)
        await pause()

        #expect(coordinator.loadedProvider == nil)
        #expect(coordinator.loadedSummary == nil)
        #expect(changeCount == 0)
    }
}

private actor GatedUsageLoader: AgentUsageLoading {
    private var loadCounts: [AgentProvider: Int] = [:]
    private var gatedProviders: Set<AgentProvider> = []
    private var waiting: [AgentProvider: [CheckedContinuation<Void, Never>]] = [:]
    private var results: [AgentProvider: AgentUsageSummary?] = [:]

    func setResult(_ provider: AgentProvider, _ summary: AgentUsageSummary?) {
        results[provider] = summary
    }

    func hold(_ provider: AgentProvider) {
        gatedProviders.insert(provider)
    }

    func release(_ provider: AgentProvider) {
        gatedProviders.remove(provider)
        let continuations = waiting[provider] ?? []
        waiting[provider] = nil
        for continuation in continuations {
            continuation.resume()
        }
    }

    func loadCount(for provider: AgentProvider) -> Int {
        loadCounts[provider] ?? 0
    }

    func loadSummary(for provider: AgentProvider) async -> AgentUsageSummary? {
        loadCounts[provider, default: 0] += 1
        if gatedProviders.contains(provider) {
            await withCheckedContinuation { continuation in
                waiting[provider, default: []].append(continuation)
            }
        }
        return results[provider] ?? nil
    }
}
