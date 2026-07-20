import Foundation
import MyTTYCore

/// Owns the 120s "which provider's usage/quota meter is showing" poll:
/// the `AgentUsageCache` actor, the timer that force-refreshes it, and the
/// request-ID bookkeeping that discards a load if the focused pane's agent
/// provider changed (or the request was superseded) before it completed.
/// Extracted from `TerminalWindowController.refreshAgentUsageIfNeeded` /
/// `startAgentUsageObservation` verbatim — the 120s interval/5s tolerance,
/// the `.common` run loop mode, and the "only refetch when the provider
/// changed or `force` is set" gating are unchanged.
///
/// `TerminalWindowController` owns this coordinator and supplies the
/// currently-focused pane's agent provider via a closure (querying
/// `AgentStatusPollingCoordinator` + `WindowSession`, both of which stay
/// controller-private) rather than this type reaching into either.
@MainActor
final class AgentUsagePollingCoordinator: NSObject {
    private(set) var loadedProvider: AgentProvider?
    private(set) var loadedSummary: AgentUsageSummary?

    private let cache: AgentUsageCache
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var requestedProvider: AgentProvider?

    private let foregroundProvider: () -> AgentProvider?
    /// Fired whenever a load completes and updates `loadedProvider` /
    /// `loadedSummary` — the controller uses this to refresh the status bar.
    private let onUsageChanged: () -> Void

    init(
        cache: AgentUsageCache = AgentUsageCache(loader: NativeAgentUsageLoader()),
        foregroundProvider: @escaping () -> AgentProvider?,
        onUsageChanged: @escaping () -> Void
    ) {
        self.cache = cache
        self.foregroundProvider = foregroundProvider
        self.onUsageChanged = onUsageChanged
        super.init()
    }

    func start() {
        let timer = Timer(
            timeInterval: 120,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshIfNeeded()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }

    @objc private func timerDidFire(_ timer: Timer) {
        refreshIfNeeded(force: true)
    }

    func refreshIfNeeded(force: Bool = false) {
        guard let provider = foregroundProvider() else {
            requestedProvider = nil
            requestID = nil
            task?.cancel()
            task = nil
            return
        }
        guard force || requestedProvider != provider else { return }

        task?.cancel()
        let newRequestID = UUID()
        requestID = newRequestID
        requestedProvider = provider
        let cache = cache
        task = Task { [weak self] in
            let summary = await cache.summary(for: provider)
            guard let self,
                  !Task.isCancelled,
                  requestID == newRequestID,
                  foregroundProvider() == provider
            else { return }
            loadedProvider = provider
            loadedSummary = summary
            task = nil
            if summary == nil {
                requestedProvider = nil
            }
            onUsageChanged()
        }
    }
}
