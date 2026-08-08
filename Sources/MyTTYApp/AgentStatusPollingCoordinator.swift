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
    /// The latest known Claude Code `--permission-mode` per surface (see
    /// `AgentProviderPollResult.permissionMode`), including a mode
    /// switched at runtime with shift+tab. Only ever populated for
    /// surfaces whose provider's runtime supplies one -- Claude Code
    /// today. Rebuilt every tick alongside `statusBySurface`, but
    /// unconditionally, so it stays current even on a tick where nothing
    /// else changed enough to trigger a UI refresh.
    private(set) var permissionModesBySurface: [TerminalSurfaceID: String] = [:]
    /// The foreground agent process's own working directory (e.g.
    /// `claude --worktree`, which chdirs the agent but not the shell that
    /// launched it), keyed by surface. Only populated for surfaces with a
    /// resolved provider — a surface running no agent has no entry here,
    /// and the controller falls back to the shell's OSC 7-reported cwd.
    private(set) var workingDirectoriesBySurface: [TerminalSurfaceID: URL] = [:]
    /// The name of each pane's foreground executable (`zsh`, `claude`, `vim`),
    /// keyed by surface. Populated for every surface with a readable
    /// foreground process, agent or not — the per-pane status bar names the
    /// running program even when no agent is involved.
    private(set) var commandNamesBySurface: [TerminalSurfaceID: String] = [:]

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
    /// what changed. `providersChanged` covers a changed foreground provider
    /// set, a changed agent working-directory set *and* a changed foreground
    /// command-name set, since all three affect the status bar/window-metadata
    /// presentation the same way.
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
    /// Reports every surface whose polled foreground provider appeared,
    /// changed, or disappeared this tick -- feeds
    /// `NativeAgentRunEstimator.providerChanged` via
    /// `NativeAgentRunCoordinator`, which needs the transition itself
    /// (not just "something changed") to know whether to end an epoch,
    /// start a new one, or both. Fired for every surface that was present
    /// before and is absent now too, with `provider: nil`, since that's
    /// how a closed pane or an agent process exiting reaches the estimator.
    private let onProviderTransition: (
        _ surfaceID: TerminalSurfaceID,
        _ provider: AgentProvider?,
        _ processID: pid_t?
    ) -> Void
    /// Reports a transcript-derived turn observation (Claude Code, Codex)
    /// so `NativeAgentRunCoordinator` can split a native-estimated run into
    /// per-turn runs -- see `AgentTurnObservation`. Fired only when the
    /// observation *changed* for that surface (`lastTurnBySurface`), the
    /// same "changed, not every tick" gate `onInterruptedRun` uses.
    private let onTurnObservation: (
        _ surfaceID: TerminalSurfaceID,
        _ provider: AgentProvider,
        _ turn: AgentTurnObservation
    ) -> Void
    private var lastTurnBySurface: [TerminalSurfaceID: AgentTurnObservation] = [:]

    init(
        surfaces: @escaping () -> [TerminalSurfaceID: GhosttySurfaceView],
        hookSessionID: @escaping (TerminalSurfaceID, AgentProvider) -> String?,
        workingDirectory: @escaping (TerminalSurfaceID) -> URL?,
        onPoll: @escaping (_ providersChanged: Bool, _ sessionIDsChanged: Bool) -> Void,
        onInterruptedRun: @escaping (
            _ surfaceID: TerminalSurfaceID,
            _ provider: AgentProvider,
            _ interruption: AgentRunInterruption
        ) -> Void = { _, _, _ in },
        onProviderTransition: @escaping (
            _ surfaceID: TerminalSurfaceID,
            _ provider: AgentProvider?,
            _ processID: pid_t?
        ) -> Void = { _, _, _ in },
        onTurnObservation: @escaping (
            _ surfaceID: TerminalSurfaceID,
            _ provider: AgentProvider,
            _ turn: AgentTurnObservation
        ) -> Void = { _, _, _ in }
    ) {
        self.surfaces = surfaces
        self.hookSessionID = hookSessionID
        self.workingDirectory = workingDirectory
        self.onPoll = onPoll
        self.onInterruptedRun = onInterruptedRun
        self.onProviderTransition = onProviderTransition
        self.onTurnObservation = onTurnObservation
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

    func workingDirectory(for surfaceID: TerminalSurfaceID?) -> URL? {
        guard let surfaceID else { return nil }
        return workingDirectoriesBySurface[surfaceID]
    }

    func permissionMode(for surfaceID: TerminalSurfaceID?) -> String? {
        guard let surfaceID else { return nil }
        return permissionModesBySurface[surfaceID]
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

    private func reportTurnObservation(
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        turn: AgentTurnObservation?
    ) {
        guard let turn else { return }
        guard lastTurnBySurface[surfaceID] != turn else { return }
        lastTurnBySurface[surfaceID] = turn
        onTurnObservation(surfaceID, provider, turn)
    }

    @discardableResult
    func refreshProviders() -> Bool {
        let currentSurfaces = surfaces()
        processProviderCache.purge(activeSurfaceIDs: currentSurfaces.keys)
        var providers: [TerminalSurfaceID: AgentProvider] = [:]
        var workingDirectories: [TerminalSurfaceID: URL] = [:]
        var commandNames: [TerminalSurfaceID: String] = [:]
        for (surfaceID, surface) in currentSurfaces {
            let resolvedProvider = processProviderCache.provider(
                surfaceID: surfaceID,
                processID: surface.foregroundProcessID
            )
            // Read before the provider guard below: a pane sitting at a
            // plain shell prompt has no provider but still has a foreground
            // process worth naming. The path comes from the cache key the
            // call above just refreshed, so this costs no extra syscall.
            if let path = processProviderCache.executablePath(for: surfaceID),
               let name = TerminalAgentProcessDetector.commandName(
                   executablePath: path
               ) {
                commandNames[surfaceID] = name
            }
            guard let provider = resolvedProvider else { continue }
            providers[surfaceID] = provider
            if let agentDirectory = TerminalAgentProcessDetector.workingDirectory(
                processID: surface.foregroundProcessID
            ) {
                workingDirectories[surfaceID] = agentDirectory.standardizedFileURL
            }
        }

        let providersChanged = providers != providersBySurface
        // Every surface whose provider mapping is different this tick,
        // including a surface that had a provider before and has none now
        // (closed pane, or the agent process exited) -- computed here,
        // where both the old and new dictionaries are still in scope,
        // rather than reconstructed from the post-assignment state below.
        if providersChanged {
            for surfaceID in Set(providers.keys).union(providersBySurface.keys)
            where providers[surfaceID] != providersBySurface[surfaceID] {
                let processID = providers[surfaceID] != nil
                    ? currentSurfaces[surfaceID]?.foregroundProcessID
                    : nil
                onProviderTransition(surfaceID, providers[surfaceID], processID)
            }
        }

        let workingDirectoriesChanged = workingDirectories != workingDirectoriesBySurface
        let commandNamesChanged = commandNames != commandNamesBySurface
        guard providersChanged || workingDirectoriesChanged || commandNamesChanged
        else { return false }
        providersBySurface = providers
        workingDirectoriesBySurface = workingDirectories
        commandNamesBySurface = commandNames
        return true
    }

    @discardableResult
    private func refreshSessionIDs() -> Bool {
        let currentSurfaces = surfaces()
        throttle.purge(activeSurfaceIDs: currentSurfaces.keys)
        reportedInterruptions = reportedInterruptions.filter {
            currentSurfaces[$0.key] != nil
        }
        lastTurnBySurface = lastTurnBySurface.filter {
            currentSurfaces[$0.key] != nil
        }

        var statuses: [TerminalSurfaceID: AgentSessionStatus] = [:]
        var permissionModes: [TerminalSurfaceID: String] = [:]
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
            if let permissionMode = result.permissionMode {
                permissionModes[surfaceID] = permissionMode
            }
            reportInterruptedRun(
                surfaceID: surfaceID,
                provider: provider,
                interruption: result.interruption
            )
            reportTurnObservation(
                surfaceID: surfaceID,
                provider: provider,
                turn: result.turn
            )
        }
        // Assigned unconditionally, ahead of the "did anything change"
        // guard below -- a permission-mode change alone doesn't need to
        // trigger a UI refresh, but a caller reading this dictionary right
        // after a poll tick (e.g. `agent spawn`'s access resolution) must
        // always see the latest read regardless of what else changed.
        permissionModesBySurface = permissionModes
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
            workingDirectory: { [weak self, workingDirectory] in
                // Prefer the agent process's own working directory (from
                // proc_pidinfo, so symlinks are resolved the same way the
                // agent itself resolves them) over the shell's OSC 7 cwd.
                // Claude Code names its transcript project directory after
                // its resolved cwd, so a pane sitting in a symlinked path
                // (e.g. ~/work -> Dropbox) never finds its transcript
                // through the OSC 7 value alone.
                self?.workingDirectoriesBySurface[surfaceID]
                    ?? workingDirectory(surfaceID)
            }
        )
    }
}
