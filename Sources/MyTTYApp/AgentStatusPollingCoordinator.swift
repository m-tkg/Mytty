import AppKit
import GhosttyAdapter
import MyTTYCore

/// Owns the 0.5s foreground-agent-process poll: which `AgentProvider` (if
/// any) is running in each pane's foreground process, and — via the
/// provider registry from `AgentProviderRuntime.swift` — that provider's
/// session status (model name, context remaining, session ID). Extracted
/// from `TerminalWindowController` verbatim; the timer interval/tolerance,
/// the `.common` run loop mode, and the change-detection (`!=`) gating that
/// decides whether a poll tick triggers a UI refresh are all unchanged.
///
/// `TerminalWindowController` remains the owner: it creates this
/// coordinator, starts/stops it alongside the window's lifecycle, and reads
/// the published dictionaries for status-bar/sidebar rendering. Everything
/// this coordinator needs from the controller (the live surfaces, the
/// hook-reported session ID, a pane's working directory) is threaded
/// through as closures so the coordinator doesn't reach back into
/// `WindowSession` or `AttentionCenter` directly.
@MainActor
final class AgentStatusPollingCoordinator: NSObject {
    private(set) var providersBySurface: [TerminalSurfaceID: AgentProvider] = [:]
    private(set) var sessionIDsBySurface: [TerminalSurfaceID: String] = [:]
    private(set) var statusBySurface: [TerminalSurfaceID: AgentSessionStatus] = [:]

    private let throttle = AgentSessionThrottleCache()
    private let processProviderCache = AgentProcessProviderCache()
    private var timer: Timer?

    private let surfaces: () -> [TerminalSurfaceID: GhosttySurfaceView]
    private let hookSessionID: (TerminalSurfaceID, AgentProvider) -> String?
    private let workingDirectory: (TerminalSurfaceID) -> URL?
    /// Fired at the end of every poll tick, mirroring the tail of the old
    /// `pollForegroundAgentProcess`. The controller decides what a changed
    /// provider/session-ID set implies (sidebar/status bar refresh, usage
    /// refresh, `onAgentActivityChanged`) — this coordinator only reports
    /// what changed.
    private let onPoll: (_ providersChanged: Bool, _ sessionIDsChanged: Bool) -> Void
    /// Reports a run the user interrupted without the provider firing a
    /// completion hook, so the controller can end it. Fired once per
    /// interrupt — the controller's event log is idempotent, but
    /// re-announcing an interrupt every 0.5s tick would still be noise.
    private let onInterruptedRun: (
        _ surfaceID: TerminalSurfaceID,
        _ provider: AgentProvider,
        _ interruption: AgentRunInterruption
    ) -> Void
    private var reportedInterruptions: [
        TerminalSurfaceID: AgentRunInterruption
    ] = [:]

    init(
        surfaces: @escaping () -> [TerminalSurfaceID: GhosttySurfaceView],
        hookSessionID: @escaping (TerminalSurfaceID, AgentProvider) -> String?,
        workingDirectory: @escaping (TerminalSurfaceID) -> URL?,
        onPoll: @escaping (_ providersChanged: Bool, _ sessionIDsChanged: Bool) -> Void,
        onInterruptedRun: @escaping (
            _ surfaceID: TerminalSurfaceID,
            _ provider: AgentProvider,
            _ interruption: AgentRunInterruption
        ) -> Void = { _, _, _ in }
    ) {
        self.surfaces = surfaces
        self.hookSessionID = hookSessionID
        self.workingDirectory = workingDirectory
        self.onPoll = onPoll
        self.onInterruptedRun = onInterruptedRun
        super.init()
    }

    func start() {
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerDidFire(_ timer: Timer) {
        poll()
    }

    func foregroundProvider(
        for surfaceID: TerminalSurfaceID?
    ) -> AgentProvider? {
        guard let surfaceID else { return nil }
        return providersBySurface[surfaceID]
    }

    private func poll() {
        let providersChanged = refreshProviders()
        let sessionIDsChanged = refreshSessionIDs()
        onPoll(providersChanged, sessionIDsChanged)
    }

    private func reportInterruptedRun(
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        interruption: AgentRunInterruption?
    ) {
        guard let interruption else {
            reportedInterruptions[surfaceID] = nil
            return
        }
        guard reportedInterruptions[surfaceID] != interruption else { return }
        reportedInterruptions[surfaceID] = interruption
        onInterruptedRun(surfaceID, provider, interruption)
    }

    @discardableResult
    func refreshProviders() -> Bool {
        let currentSurfaces = surfaces()
        processProviderCache.purge(activeSurfaceIDs: currentSurfaces.keys)
        let providers = currentSurfaces.reduce(
            into: [TerminalSurfaceID: AgentProvider]()
        ) { result, entry in
            guard let provider = processProviderCache.provider(
                surfaceID: entry.key,
                processID: entry.value.foregroundProcessID
            ) else { return }
            result[entry.key] = provider
        }
        guard providers != providersBySurface else { return false }
        providersBySurface = providers
        return true
    }

    @discardableResult
    private func refreshSessionIDs() -> Bool {
        let currentSurfaces = surfaces()
        throttle.purge(activeSurfaceIDs: currentSurfaces.keys)
        reportedInterruptions = reportedInterruptions.filter {
            currentSurfaces[$0.key] != nil
        }

        var statuses: [TerminalSurfaceID: AgentSessionStatus] = [:]
        for (surfaceID, surface) in currentSurfaces {
            guard let provider = providersBySurface[surfaceID],
                  let runtime = AgentProviderRuntimeRegistry.runtime(
                      for: provider
                  )
            else { continue }

            let result = runtime.poll(
                context: queryContext(
                    surfaceID: surfaceID,
                    surface: surface,
                    provider: provider
                ),
                throttle: throttle
            )
            statuses[surfaceID] = result.status
            reportInterruptedRun(
                surfaceID: surfaceID,
                provider: provider,
                interruption: result.interruption
            )
        }
        let sessionIDs = statuses.reduce(
            into: [TerminalSurfaceID: String]()
        ) { result, entry in
            result[entry.key] = entry.value.sessionID
        }
        guard sessionIDs != sessionIDsBySurface
                || statuses != statusBySurface
        else { return false }
        sessionIDsBySurface = sessionIDs
        statusBySurface = statuses
        return true
    }

    private func queryContext(
        surfaceID: TerminalSurfaceID,
        surface: GhosttySurfaceView,
        provider: AgentProvider
    ) -> AgentSessionQueryContext {
        AgentSessionQueryContext(
            surfaceID: surfaceID,
            surface: surface,
            hookSessionID: { [hookSessionID] in
                hookSessionID(surfaceID, provider)
            },
            workingDirectory: { [workingDirectory] in
                workingDirectory(surfaceID)
            }
        )
    }
}
