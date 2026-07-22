import AppKit
import Combine
import GhosttyAdapter
import MyTTYCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum TerminalWindowGeometry {
    static let styleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
    ]

    static func contentRect(forWindowFrame frame: NSRect) -> NSRect {
        NSWindow.contentRect(forFrameRect: frame, styleMask: styleMask)
    }

    static func apply(_ frame: NSRect, to window: NSWindow) {
        window.setFrame(frame, display: false)
    }

    static func installContentViewController(
        _ controller: NSViewController,
        in window: NSWindow
    ) {
        let frame = window.frame
        window.contentViewController = controller
        apply(frame, to: window)
    }
}

enum TerminalWindowTitle {
    static func make(
        baseTitle: String,
        activeProvider: AgentProvider?
    ) -> String {
        guard let activeProvider else { return baseTitle }
        return "\(name(for: activeProvider)) - \(baseTitle)"
    }

    static func name(for provider: AgentProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        case .antigravity: "Gemini (Antigravity)"
        case .cursor: "Cursor"
        }
    }
}

enum TerminalTabTitle {
    static func defaultTitle(
        for tab: TabSession,
        localizer: MyTTYLocalizer
    ) -> String {
        guard let firstPaneID = tab.paneIDs.first else {
            return localizer[.terminal]
        }
        if let terminal = tab.root.surfaceState(with: firstPaneID) {
            let url = terminal.workingDirectory
            return url.path == "/" ? "/" : url.lastPathComponent
        }
        if let browser = tab.root.browserState(with: firstPaneID) {
            let url = browser.url
            if url.isFileURL {
                return url.lastPathComponent.isEmpty
                    ? localizer[.browser]
                    : url.lastPathComponent
            }
            return url.host(percentEncoded: false)
                ?? (url.absoluteString.isEmpty
                    ? localizer[.browser]
                    : url.absoluteString)
        }
        return localizer[.terminal]
    }
}

@MainActor
struct TerminalTabTransfer {
    let tab: TabSession
    let surfaces: [TerminalSurfaceID: GhosttySurfaceView]
    let browsers: [TerminalSurfaceID: BrowserPaneView]
}

/// How a session save sources each pane's scrollback. Capturing it means
/// reading every live pane's VT screen — tens of milliseconds per pane — so
/// only the saves that exist to preserve terminal content pay for it.
enum TerminalHistoryCapture {
    case fresh
    case reusingLastCapture
}

@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    private let runtime: GhosttyRuntime
    private let attentionCenter: AttentionCenter
    private let agentEventServer: AgentEventServer
    private let paneInputScheduler: PaneInputScheduler
    private let sidebarModel = TabSidebarModel()
    private let statusBarModel = TerminalStatusBarModel()
    private let titlebarView = TerminalTitlebarView()
    private let surfaceHost = NSView()
    private var surfaces: [TerminalSurfaceID: GhosttySurfaceView] = [:]
    private lazy var autocomplete = TerminalAutocompleteCoordinator(
        isEnabled: { [weak self] in
            self?.applicationPreferences.autocompleteEnabled ?? false
        },
        surface: { [weak self] surfaceID in self?.surfaces[surfaceID] },
        activeSurfaceIDs: { [weak self] in
            self?.surfaces.keys.map { $0 } ?? []
        }
    )
    private var browsers: [TerminalSurfaceID: BrowserPaneView] = [:]
    private var attentionObserver: AnyCancellable?
    private lazy var scheduledInput = ScheduledInputCoordinator(
        scheduler: paneInputScheduler,
        localizer: localizer,
        surface: { [weak self] surfaceID in self?.surfaces[surfaceID] },
        presentError: { [weak self] error in self?.presentActionError(error) },
        onSchedulesChanged: { [weak self] schedules in
            self?.updateScheduledInputStatus(schedules)
        }
    )
    private var renderedTabID: TabID?
    private var capturedTerminalHistories: [TerminalSurfaceID: String] = [:]
    private lazy var paneLayout = PaneLayoutController(
        surfaceHost: surfaceHost,
        surfaces: { [weak self] in self?.surfaces ?? [:] },
        browsers: { [weak self] in self?.browsers ?? [:] },
        inactivePaneDimming: { [weak self] in
            CGFloat(self?.applicationPreferences.inactivePaneDimming ?? 0)
        },
        activePaneBorder: { [weak self] in
            self?.activePaneBorderStyle ?? .hidden
        },
        isLiveResizing: { [weak self] in self?.isWindowLiveResizing ?? false },
        onRatioChanged: { [weak self] ratio, path in
            guard let self else { return }
            do {
                try self.session.updateSelectedSplitRatio(ratio, at: path)
                self.sessionDidChange()
            } catch {
                self.presentActionError(error)
            }
        },
        onSizeIndicatorsChanged: { [weak self] in self?.updateStatusBar() }
    )
    private var tabPlacement: MyTTYTabPlacement
    private var applicationPreferences: ApplicationPreferences
    private var localizer: MyTTYLocalizer
    private var tabPanelsPresented = true
    private var isAttachingSelectedTab = false
    private var swapPanesFirstSelection: TerminalSurfaceID?
    private var swapPanesCursorID: TerminalSurfaceID?
    private var swapPanesKeyMonitor: Any?
    private var isSwapPanesModeActive = false
    private var bypassNextWindowConfirmation = false
    private var pendingLinkURL: URL?
    private var isWindowLiveResizing = false
    private lazy var agentUsagePolling = AgentUsagePollingCoordinator(
        foregroundProvider: { [weak self] in self?.foregroundAgentProvider },
        onUsageChanged: { [weak self] in self?.updateStatusBar() }
    )
    private lazy var agentStatusPolling = AgentStatusPollingCoordinator(
        surfaces: { [weak self] in self?.surfaces ?? [:] },
        hookSessionID: { [weak self] surfaceID, provider in
            self?.attentionCenter.latestRun(
                for: surfaceID,
                provider: provider
            )?.sessionID
        },
        workingDirectory: { [weak self] surfaceID in
            self?.surfaceWorkingDirectory(for: surfaceID)
        },
        onPoll: { [weak self] providersChanged, sessionIDsChanged in
            self?.handleAgentStatusPoll(
                providersChanged: providersChanged,
                sessionIDsChanged: sessionIDsChanged
            )
        },
        onInterruptedRun: { [weak self] surfaceID, provider, interruption in
            self?.handleInterruptedAgentRun(
                surfaceID: surfaceID,
                provider: provider,
                interruption: interruption
            )
        }
    )
    private lazy var repositoryStatus = RepositoryStatusCoordinator(
        focusedDirectory: { [weak self] in self?.focusedTerminalDirectory },
        onStatusChanged: { [weak self] in self?.updateStatusBar() }
    )
    private lazy var recording = TerminalRecordingCoordinator(
        showPressedKeyToast: { [weak self] in
            self?.applicationPreferences.showPressedKeyToast ?? false
        },
        outputPanelTitle: { [weak self] in
            self?.localizer[.terminalRecording] ?? ""
        },
        onRecordingStateChanged: { [weak self] in self?.refreshSidebarRows() },
        presentError: { [weak self] error in self?.presentActionError(error) }
    )
    private lazy var remotePane = RemotePaneBridge(
        surface: { [weak self] paneID in self?.surfaces[paneID] },
        onConnectedChanged: { [weak self] connected in
            self?.sidebarModel.isRemoteAccessConnected = connected
        }
    )
    private lazy var tabDrag = TabDragController(
        coordinator: tabDragCoordinator,
        windowID: { [weak self] in self?.session.id ?? WindowID() },
        window: { [weak self] in self?.window },
        tabExists: { [weak self] tabID in
            self?.session.tabs.contains { $0.id == tabID } ?? false
        },
        tabIndex: { [weak self] tabID in
            self?.session.tabs.firstIndex { $0.id == tabID }
        },
        sidebarRow: { [weak self] tabID in
            self?.sidebarModel.rows.first { $0.id == tabID }
        },
        selectedTabID: { [weak self] in self?.sidebarModel.selectedTabID },
        tabPlacement: { [weak self] in self?.tabPlacement ?? .left },
        localizer: { [weak self] in
            self?.localizer ?? MyTTYLocalizer(language: .english)
        },
        clearPromotedDragTabID: { [weak self] in
            self?.sidebarModel.promotedDragTabID = nil
        },
        onTabDropRequested: { [weak self] index in
            self?.onTabDropRequested(index)
        },
        onMove: { [weak self] id, destination in
            self?.performTabMove(id, to: destination)
        },
        onTabDragSessionEnded: { [weak self] id, point in
            self?.onTabDragSessionEnded(id, point)
        }
    )
    private var agentSleepStatus: AgentSleepStatus = .disabled
    private var paneExplanationPanel: PaneExplanationPanelController?
    private var paneExplanationTask: Task<Void, Never>?
    private var commandSummaryPanel: PaneExplanationPanelController?
    private var commandSummaryTask: Task<Void, Never>?
    private var lastCommandResultBySurface:
        [TerminalSurfaceID: LastCommandResult] = [:]

    private var foregroundAgentProvider: AgentProvider? {
        agentStatusPolling.foregroundProvider(
            for: session.selectedTab?.focusedSurfaceID
        )
    }

    private let tabDragCoordinator: TabDragCoordinator
    private let closedPaneHistory: ClosedPaneHistory
    private let onSessionChanged: (WindowSession) -> Void
    private let onWindowClosed: (WindowID) -> Void
    private let onNewWindowRequested: (URL) -> Void
    private let onFocusSurfaceRequested: (TerminalSurfaceID) -> Void
    private let onAgentActivityChanged: () -> Void
    private let onSleepPreventionModeSelected: (AgentSleepPreventionMode) -> Void
    private let onTabDropRequested: (Int) -> Void
    private let onTabDragSessionEnded: (TabID, NSPoint) -> Void

    private(set) var session: WindowSession

    init(
        session: WindowSession,
        runtime: GhosttyRuntime,
        attentionCenter: AttentionCenter,
        agentEventServer: AgentEventServer,
        paneInputScheduler: PaneInputScheduler,
        applicationPreferences: ApplicationPreferences,
        tabDragCoordinator: TabDragCoordinator,
        closedPaneHistory: ClosedPaneHistory,
        adopting transfer: TerminalTabTransfer? = nil,
        onSessionChanged: @escaping (WindowSession) -> Void,
        onWindowClosed: @escaping (WindowID) -> Void,
        onNewWindowRequested: @escaping (URL) -> Void,
        onFocusSurfaceRequested: @escaping (TerminalSurfaceID) -> Void,
        onAgentActivityChanged: @escaping () -> Void,
        onSleepPreventionModeSelected: @escaping (AgentSleepPreventionMode) -> Void,
        onTabDropRequested: @escaping (Int) -> Void,
        onTabDragSessionEnded: @escaping (TabID, NSPoint) -> Void
    ) throws {
        self.session = session
        // Seed the cache from what the session was restored (or adopted)
        // with: until the first fresh capture, a routine save must write
        // that scrollback back rather than erase it.
        self.capturedTerminalHistories = session.tabs
            .flatMap(\.root.surfaceStates)
            .reduce(into: [TerminalSurfaceID: String]()) { result, state in
                result[state.id] = state.terminalHistory
            }
        self.runtime = runtime
        self.attentionCenter = attentionCenter
        self.agentEventServer = agentEventServer
        self.paneInputScheduler = paneInputScheduler
        self.tabPlacement = applicationPreferences.tabPlacement
        self.applicationPreferences = applicationPreferences
        self.localizer = MyTTYLocalizer(
            language: applicationPreferences.language
        )
        self.tabDragCoordinator = tabDragCoordinator
        self.closedPaneHistory = closedPaneHistory
        self.onSessionChanged = onSessionChanged
        self.onWindowClosed = onWindowClosed
        self.onNewWindowRequested = onNewWindowRequested
        self.onFocusSurfaceRequested = onFocusSurfaceRequested
        self.onAgentActivityChanged = onAgentActivityChanged
        self.onSleepPreventionModeSelected =
            onSleepPreventionModeSelected
        self.onTabDropRequested = onTabDropRequested
        self.onTabDragSessionEnded = onTabDragSessionEnded

        let windowFrame = NSRect(
            x: session.frame.x,
            y: session.frame.y,
            width: session.frame.width,
            height: session.frame.height
        )
        let window = NSWindow(
            contentRect: TerminalWindowGeometry.contentRect(
                forWindowFrame: windowFrame
            ),
            styleMask: TerminalWindowGeometry.styleMask,
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        configureWindow(window)
        TerminalWindowGeometry.apply(windowFrame, to: window)
        moveOnscreenIfNeeded(window)
        do {
            try createInitialSurfaces(adopting: transfer)
        } catch {
            revokeSurfaceCapabilities()
            throw error
        }
        observeAttention()
        scheduledInput.startObserving()
        refreshPresentation(focusTerminal: false)
        agentStatusPolling.start()
        agentUsagePolling.start()
        repositoryStatus.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var currentWorkingDirectory: URL {
        guard let tab = session.selectedTab else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return tab.root.surfaceState(with: tab.focusedSurfaceID)?.workingDirectory
            ?? tab.root.surfaceStates.first?.workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var hasProcessingAgent: Bool {
        TerminalTabAgentActivity.isProcessing(
            surfaceIDs: Array(surfaces.keys),
            foregroundProvidersBySurface: agentStatusPolling.providersBySurface,
            lifecycleBySurface: agentLifecycleBySurface
        )
    }

    var hasLaunchedAgent: Bool {
        !agentStatusPolling.providersBySurface.isEmpty
    }

    func sessionSnapshotForRestoration(
        history: TerminalHistoryCapture = .fresh
    ) -> WindowSession {
        let activeResumes = surfaces.keys.reduce(
            into: [TerminalSurfaceID: AgentResumeDescriptor]()
        ) { result, surfaceID in
            result[surfaceID] = activeAgentResume(for: surfaceID)
        }
        var snapshot = AgentSessionRestoration.snapshot(
            session,
            activeResumes: activeResumes
        )
        for (surfaceID, terminalHistory) in terminalHistories(history) {
            try? snapshot.updateTerminalHistory(
                terminalHistory,
                for: surfaceID
            )
        }
        return snapshot
    }

    /// Reading a pane's scrollback costs tens of milliseconds, so only a
    /// `.fresh` capture pays for it; every other save reuses what the last
    /// one stored.
    private func terminalHistories(
        _ capture: TerminalHistoryCapture
    ) -> [TerminalSurfaceID: String] {
        switch capture {
        case .fresh:
            capturedTerminalHistories = surfaces.compactMapValues {
                TerminalHistory.bounded(
                    TerminalHistory.sanitized($0.screenVTText())
                )
            }
        case .reusingLastCapture:
            capturedTerminalHistories = capturedTerminalHistories.filter {
                surfaces[$0.key] != nil
            }
        }
        return capturedTerminalHistories
    }

    func isSurfaceVisible(_ surfaceID: TerminalSurfaceID) -> Bool {
        guard session.selectedTab?.surfaceIDs.contains(surfaceID) == true,
              surfaces[surfaceID]?.window != nil,
              let window,
              window.isVisible,
              !window.isMiniaturized
        else { return false }
        return window.occlusionState.contains(.visible)
    }

    func isSurfaceActivelyFocused(_ surfaceID: TerminalSurfaceID) -> Bool {
        guard NSApplication.shared.isActive,
              session.selectedTab?.focusedSurfaceID == surfaceID,
              let window,
              window.isKeyWindow
        else { return false }
        return isSurfaceVisible(surfaceID)
    }

    /// True when `surfaceID` was created through the mytty-ctl control
    /// surface (`new-tab`, `split`, `agent spawn`). Such panes never raise
    /// attention notifications — see `AppDelegate.receiveAgentEvent`.
    func isOrchestratedSurface(_ surfaceID: TerminalSurfaceID) -> Bool {
        session.tabs.contains {
            $0.root.surfaceState(with: surfaceID)?.isOrchestrated == true
        }
    }

    @discardableResult
    func newTab(
        workingDirectory: URL? = nil,
        initialInput: String? = nil,
        orchestrated: Bool = false
    ) -> TerminalSurfaceID? {
        let state = TerminalSurfaceState(
            workingDirectory: workingDirectory ?? currentWorkingDirectory,
            isOrchestrated: orchestrated
        )
        do {
            let tab = TabSession(initialSurface: state)
            let surface = try makeSurface(for: state, initialInput: initialInput)
            switch applicationPreferences.newTabPosition {
            case .end:
                try session.add(tab: tab, select: true)
            case .afterCurrent:
                if let currentIndex = session.tabs.firstIndex(
                    where: { $0.id == session.selectedTabID }
                ) {
                    try session.insert(
                        tab: tab,
                        at: currentIndex + 1,
                        select: true
                    )
                } else {
                    try session.add(tab: tab, select: true)
                }
            }
            surfaces[state.id] = surface
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            return state.id
        } catch {
            agentEventServer.revoke(surface: state.id)
            autocomplete.removeSession(for: state.id)
            presentActionError(error)
            return nil
        }
    }

    func openHTMLFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        panel.directoryURL = currentWorkingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openBrowserTab(url)
    }

    private func openBrowserTab(_ url: URL) {
        let state = BrowserPaneState(url: url)
        do {
            let browser = makeBrowser(for: state)
            try session.add(
                tab: TabSession(initialBrowser: state),
                select: true
            )
            browsers[state.id] = browser
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    private func openBrowserPane(
        _ url: URL,
        direction: SplitDirection
    ) {
        let state = BrowserPaneState(url: url)
        do {
            let browser = makeBrowser(for: state)
            try session.splitFocusedBrowser(
                adding: state,
                direction: direction
            )
            browsers[state.id] = browser
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    func select(tab id: TabID) {
        exitSwapPanesMode()
        do {
            try session.select(tab: id)
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    /// Jumps to the `number`-th tab (1-based), matching sidebar row
    /// numbering top to bottom. Out-of-range numbers (fewer tabs than
    /// `number`) are ignored rather than clamped to the last tab.
    func selectTab(number: Int) {
        let index = number - 1
        guard session.tabs.indices.contains(index) else { return }
        select(tab: session.tabs[index].id)
    }

    /// Cycles to the tab `offset` positions from the selected one,
    /// wrapping around at either end.
    func selectAdjacentTab(offset: Int) {
        guard let currentIndex = session.tabs.firstIndex(where: {
            $0.id == session.selectedTabID
        }), let targetIndex = CyclicSelection.index(
            current: currentIndex,
            offset: offset,
            count: session.tabs.count
        ) else { return }
        select(tab: session.tabs[targetIndex].id)
    }

    func closeSelectedTab() {
        close(tab: session.selectedTabID)
    }

    func renameSelectedTab() {
        rename(tab: session.selectedTabID)
    }

    @discardableResult
    func splitFocusedPane(
        _ direction: SplitDirection,
        workingDirectory: URL? = nil,
        initialInput: String? = nil,
        orchestrated: Bool = false
    ) -> TerminalSurfaceID? {
        let state = TerminalSurfaceState(
            workingDirectory: workingDirectory ?? currentWorkingDirectory,
            isOrchestrated: orchestrated
        )
        let focusedPaneSize = session.selectedTab.flatMap {
            paneLayout.host(for: $0.focusedSurfaceID)?.bounds.size
        }
        let initialSize = focusedPaneSize.map {
            Self.initialSurfaceSize(
                for: direction,
                focusedPaneSize: $0
            )
        }
        do {
            let surface = try makeSurface(
                for: state,
                initialSize: initialSize,
                initialInput: initialInput
            )
            do {
                try session.splitFocusedSurface(
                    adding: state,
                    direction: direction
                )
            } catch {
                agentEventServer.revoke(surface: state.id)
                autocomplete.removeSession(for: state.id)
                throw error
            }
            surfaces[state.id] = surface
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            return state.id
        } catch {
            presentActionError(error)
            return nil
        }
    }

    /// Splits a specific pane rather than whatever happens to be focused —
    /// `mytty-ctl split <paneID>` targets a pane by ID, which may not be
    /// the one the user is currently looking at. Focusing first reuses
    /// `splitFocusedPane` instead of duplicating its layout math.
    @discardableResult
    func splitPane(
        _ paneID: TerminalSurfaceID,
        direction: SplitDirection,
        workingDirectory: URL? = nil,
        initialInput: String? = nil,
        orchestrated: Bool = false
    ) -> TerminalSurfaceID? {
        guard focus(pane: paneID) else { return nil }
        return splitFocusedPane(
            direction,
            workingDirectory: workingDirectory,
            initialInput: initialInput,
            orchestrated: orchestrated
        )
    }

    func closeFocusedPane() {
        guard let tab = session.selectedTab else { return }
        closePaneOrContainingTab(tab.focusedSurfaceID)
    }

    func focusPane(_ direction: SplitDirection) {
        guard session.focusPane(in: direction) else { return }
        sessionDidChange()
        refreshPresentation(focusTerminal: true)
    }

    func equalizePanes() {
        equalizePanes(in: session.selectedTabID)
    }

    func togglePaneZoom() {
        guard let tab = session.selectedTab,
              tab.paneIDs.count > 1
        else { return }
        paneLayout.toggleZoom(for: tab)
        refreshPresentation(focusTerminal: true)
    }

    func toggleSwapPanesMode() {
        if isSwapPanesModeActive {
            exitSwapPanesMode()
        } else {
            enterSwapPanesMode()
        }
    }

    private func enterSwapPanesMode() {
        guard let tab = session.selectedTab,
              tab.paneIDs.count > 1
        else { return }
        isSwapPanesModeActive = true
        swapPanesFirstSelection = nil
        swapPanesCursorID = tab.focusedSurfaceID
        paneLayout.enableSwapClickCatchers { [weak self] id in
            self?.handleSwapPaneClicked(id)
        }
        paneLayout.updateSwapCursor(swapPanesCursorID)
        startSwapPanesKeyMonitor()
        showSwapModeHint(localizer[.selectPaneToSwap], at: tab.focusedSurfaceID)
    }

    private func exitSwapPanesMode() {
        guard isSwapPanesModeActive else { return }
        isSwapPanesModeActive = false
        swapPanesFirstSelection = nil
        swapPanesCursorID = nil
        stopSwapPanesKeyMonitor()
        paneLayout.disableSwapClickCatchers()
        paneLayout.updateSwapCandidate(nil)
        paneLayout.updateSwapCursor(nil)
        paneLayout.hideKeyToasts()
    }

    private func handleSwapPaneClicked(_ id: TerminalSurfaceID) {
        guard isSwapPanesModeActive else { return }
        swapPanesCursorID = id
        paneLayout.updateSwapCursor(id)
        pickSwapPane(id)
    }

    /// Installs a local key-down monitor for the plain arrow keys and
    /// Return while swap-panes mode is active. A monitor (mirroring
    /// `PaneListWindowController`'s navigation handling) reaches the app
    /// regardless of which pane — terminal or browser — currently holds
    /// keyboard focus, unlike `GhosttySurfaceView.onKeyIntercept`, which
    /// only exists on terminal surfaces.
    private func startSwapPanesKeyMonitor() {
        guard swapPanesKeyMonitor == nil else { return }
        swapPanesKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self,
                  self.isSwapPanesModeActive,
                  event.window === self.window,
                  event.modifierFlags.intersection([
                      .command, .control, .option, .shift,
                  ]).isEmpty
            else { return event }

            switch event.keyCode {
            case 126: self.moveSwapCursor(.up)
            case 125: self.moveSwapCursor(.down)
            case 123: self.moveSwapCursor(.left)
            case 124: self.moveSwapCursor(.right)
            case 36, 76: self.confirmSwapCursor()
            default: return event
            }
            return nil
        }
    }

    private func stopSwapPanesKeyMonitor() {
        guard let monitor = swapPanesKeyMonitor else { return }
        NSEvent.removeMonitor(monitor)
        swapPanesKeyMonitor = nil
    }

    private func moveSwapCursor(_ direction: SplitDirection) {
        guard let tab = session.selectedTab else { return }
        let currentID = swapPanesCursorID ?? tab.focusedSurfaceID
        guard let neighbor = tab.neighborPane(of: currentID, in: direction)
        else { return }
        swapPanesCursorID = neighbor
        paneLayout.updateSwapCursor(neighbor)
    }

    private func confirmSwapCursor() {
        guard let id = swapPanesCursorID else { return }
        pickSwapPane(id)
    }

    private func pickSwapPane(_ id: TerminalSurfaceID) {
        guard let firstID = swapPanesFirstSelection else {
            swapPanesFirstSelection = id
            paneLayout.updateSwapCandidate(id)
            showSwapModeHint(localizer[.selectSecondPaneToSwap], at: id)
            return
        }
        if firstID == id {
            swapPanesFirstSelection = nil
            paneLayout.updateSwapCandidate(nil)
            showSwapModeHint(localizer[.selectPaneToSwap], at: id)
            return
        }

        exitSwapPanesMode()
        do {
            try session.swapPanes(firstID, id)
            sessionDidChange()
            renderedTabID = nil
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    private func showSwapModeHint(_ text: String, at surfaceID: TerminalSurfaceID) {
        guard let host = paneLayout.host(for: surfaceID) else { return }
        let anchor = NSRect(
            x: host.bounds.midX - 5,
            y: host.bounds.maxY - 60,
            width: 10,
            height: 10
        )
        host.showKeyToast(text, below: anchor, duration: .milliseconds(2_000))
    }

    func equalizePanes(in tabID: TabID) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }),
              tab.paneIDs.count > 1
        else { return }

        do {
            try session.equalizePanes(in: tabID)
            sessionDidChange()
            guard session.selectedTabID == tabID else { return }
            renderedTabID = nil
            refreshPresentation(focusTerminal: true)
            paneLayout.showSizeIndicatorsTemporarily()
        } catch {
            presentActionError(error)
        }
    }

    func toggleAttention() {
        sidebarModel.isAttentionPresented.toggle()
        if !sidebarModel.isAttentionPresented {
            focusSelectedSurface()
        }
    }

    func setRemoteAccessConnected(_ connected: Bool) {
        remotePane.setConnected(connected)
    }

    func toggleTabPanels() {
        tabPanelsPresented.toggle()
        rebuildChrome()
        refreshPresentation(focusTerminal: true)
    }

    func toggleRecording() {
        if recording.isRecording {
            recording.stop()
            return
        }
        guard let tab = session.selectedTab,
              let surface = surfaces[tab.focusedSurfaceID]
        else {
            presentActionError(TerminalRecordingError.terminalPaneRequired)
            return
        }
        recording.start(
            tabID: tab.id,
            surfaceID: tab.focusedSurfaceID,
            surface: surface
        )
    }

    func findInFocusedPane() {
        guard let tab = session.selectedTab else { return }
        if let (browserID, browser) = browsers.first(where: {
            tab.paneIDs.contains($0.key)
                && $0.value.containsFirstResponder(window?.firstResponder)
        }) {
            focusBrowserPane(browserID)
            browser.showFind()
            return
        }
        let focusedID = tab.focusedSurfaceID
        if let surface = surfaces[focusedID] {
            surface.showSearch()
        } else {
            browsers[focusedID]?.showFind()
        }
    }

    /// macOS 26+ only: explains what the focused terminal pane has been
    /// doing, using the on-device model. Shows a floating panel with a
    /// spinner while the model runs; browser panes are not explainable.
    func explainFocusedPane() {
        guard #available(macOS 26, *),
              let tab = session.selectedTab,
              let surface = surfaces[tab.focusedSurfaceID]
        else { return }
        let panel = paneExplanationPanel
            ?? PaneExplanationPanelController(title: localizer[.explainPane])
        paneExplanationPanel = panel
        panel.beginAnalyzing(
            statusText: localizer[.paneExplanationAnalyzing],
            near: window
        )
        guard PaneExplainer.isAvailable else {
            panel.showFailure(localizer[.paneExplanationUnavailable])
            return
        }
        let buffer = surface.screenText()
        let language = applicationPreferences.language.resolved()
        let failureText = localizer[.paneExplanationFailed]
        paneExplanationTask?.cancel()
        paneExplanationTask = Task { @MainActor [weak self] in
            let explanation = await PaneExplainer.explain(
                buffer: buffer,
                language: language
            )
            guard let self, !Task.isCancelled else { return }
            if let explanation {
                self.paneExplanationPanel?.show(explanation: explanation)
            } else {
                self.paneExplanationPanel?.showFailure(failureText)
            }
        }
    }

    /// macOS 26+ only: summarizes the focused terminal's last command
    /// result in detail — including what any errors mean — with the
    /// on-device model, in a floating panel.
    func summarizeLastCommandResult() {
        guard #available(macOS 26, *),
              let tab = session.selectedTab,
              let surface = surfaces[tab.focusedSurfaceID]
        else { return }
        let panel = commandSummaryPanel
            ?? PaneExplanationPanelController(
                title: localizer[.summarizeLastCommand]
            )
        commandSummaryPanel = panel
        panel.beginAnalyzing(
            statusText: localizer[.commandSummaryAnalyzing],
            near: window
        )
        guard CommandResultSummarizer.isAvailable else {
            panel.showFailure(localizer[.paneExplanationUnavailable])
            return
        }
        let buffer = surface.screenText()
        let result = lastCommandResultBySurface[tab.focusedSurfaceID]
        let language = applicationPreferences.language.resolved()
        let failureText = localizer[.paneExplanationFailed]
        commandSummaryTask?.cancel()
        commandSummaryTask = Task { @MainActor [weak self] in
            let summary = await CommandResultSummarizer.summarize(
                buffer: buffer,
                result: result,
                language: language
            )
            guard let self, !Task.isCancelled else { return }
            if let summary {
                self.commandSummaryPanel?.show(explanation: summary)
            } else {
                self.commandSummaryPanel?.showFailure(failureText)
            }
        }
    }

    private var activePaneBorderStyle: PaneActiveBorderStyle {
        Self.activePaneBorderStyle(for: applicationPreferences)
    }

    private static func activePaneBorderStyle(
        for preferences: ApplicationPreferences
    ) -> PaneActiveBorderStyle {
        guard preferences.activePaneBorderEnabled else { return .hidden }
        return PaneActiveBorderStyle(
            width: CGFloat(preferences.activePaneBorderWidth),
            colorHex: preferences.activePaneBorderColorHex
        )
    }

    func updateApplicationPreferences(
        _ preferences: ApplicationPreferences
    ) {
        let languageChanged = preferences.language
            != applicationPreferences.language
        let placementChanged = preferences.tabPlacement != tabPlacement
        let statusBarChanged = preferences.showStatusBar
            != applicationPreferences.showStatusBar
        let attentionUnreadOnlyChanged = preferences.attentionUnreadOnly
            != applicationPreferences.attentionUnreadOnly
        let autocompleteDisabled = applicationPreferences.autocompleteEnabled
            && !preferences.autocompleteEnabled
        let keyToastDisabled = applicationPreferences.showPressedKeyToast
            && !preferences.showPressedKeyToast
        let inactiveDimmingChanged = applicationPreferences.inactivePaneDimming
            != preferences.inactivePaneDimming
        let activeBorderChanged = activePaneBorderStyle
            != Self.activePaneBorderStyle(for: preferences)
        applicationPreferences = preferences
        recording.updateShowPressedKeys(
            preferences.showPressedKeyToast
        )
        localizer = MyTTYLocalizer(language: preferences.language)
        scheduledInput.updateLocalizer(localizer)
        let terminalSearchLabels = makeTerminalSearchLabels()
        surfaces.values.forEach {
            $0.updateSearchLabels(terminalSearchLabels)
            $0.updateContextMenuLabels(makeTerminalContextMenuLabels())
        }
        let browserFindLabels = makeBrowserFindLabels()
        browsers.values.forEach {
            $0.updateFindLabels(browserFindLabels)
        }
        tabPlacement = preferences.tabPlacement
        if autocompleteDisabled {
            autocomplete.clearSuggestions()
        }
        if keyToastDisabled {
            hidePressedKeyToasts()
        }
        if inactiveDimmingChanged {
            paneLayout.updateInactiveDimming()
        }
        if activeBorderChanged {
            paneLayout.updateActiveBorder()
        }
        if languageChanged || placementChanged || statusBarChanged
            || attentionUnreadOnlyChanged {
            rebuildChrome()
            refreshPresentation(focusTerminal: false)
        }
    }

    func updateAgentSleepStatus(_ status: AgentSleepStatus) {
        guard agentSleepStatus != status else { return }
        agentSleepStatus = status
        updateStatusBar()
    }

    func refreshTerminalPresentation() {
        guard let window else { return }
        Self.prepareWindowForLiveTransparency(window)
        Self.installTitlebar(titlebarView, in: window)
        surfaces.values.forEach { $0.refresh() }
    }

    func showPressedKey(_ event: NSEvent) {
        guard applicationPreferences.showPressedKeyToast,
              let tab = session.selectedTab,
              let surface = surfaces[tab.focusedSurfaceID],
              window?.firstResponder === surface,
              let text = TerminalKeyLabel.text(for: event)
        else { return }

        recording.noteKey(event, forSurface: tab.focusedSurfaceID)
        if let host = paneLayout.host(for: tab.focusedSurfaceID) {
            let cursorRect = surface.convert(
                surface.terminalCursorRect,
                to: host
            )
            host.showKeyToast(text, below: cursorRect)
        }
        if paneLayout.zoomedPaneID == tab.focusedSurfaceID {
            if let host = paneLayout.zoomedHost {
                let cursorRect = surface.convert(
                    surface.terminalCursorRect,
                    to: host
                )
                host.showKeyToast(text, below: cursorRect)
            }
        }
    }

    private func hidePressedKeyToasts() {
        paneLayout.hideKeyToasts()
    }

    @discardableResult
    func focus(surface surfaceID: TerminalSurfaceID) -> Bool {
        guard session.tabs.contains(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else { return false }

        do {
            try session.focus(surface: surfaceID)
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            window?.makeKeyAndOrderFront(nil)
            return true
        } catch {
            presentActionError(error)
            return false
        }
    }

    func paneListSnapshot() -> PaneListWindowSnapshot {
        let commands = surfaces.reduce(
            into: [TerminalSurfaceID: String]()
        ) { result, entry in
            let processID = entry.value.foregroundProcessID
            result[entry.key] = PaneListPresentation.commandName(
                executableName: TerminalAgentProcessDetector.commandName(
                    processID: processID
                ),
                provider: TerminalAgentProcessDetector.provider(
                    processID: processID
                )
            )
        }
        return PaneListWindowSnapshot(
            session: session,
            commandsByPane: commands
        )
    }

    @discardableResult
    func focus(pane paneID: TerminalSurfaceID) -> Bool {
        guard session.tabs.contains(where: {
            $0.paneIDs.contains(paneID)
        }) else { return false }

        do {
            try session.focus(pane: paneID)
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            window?.makeKeyAndOrderFront(nil)
            return true
        } catch {
            presentActionError(error)
            return false
        }
    }

    func close(tab id: TabID) {
        close(tab: id, requiresConfirmation: true)
    }

    private func close(
        tab id: TabID,
        requiresConfirmation: Bool
    ) {
        guard let tab = session.tabs.first(where: { $0.id == id }) else {
            return
        }

        if session.tabs.count == 1 {
            guard !requiresConfirmation || confirmCloseIfNeeded(
                target: .tab,
                surfaceIDs: tab.surfaceIDs
            ) else { return }
            bypassNextWindowConfirmation = true
            window?.performClose(nil)
            return
        }

        guard !requiresConfirmation || confirmCloseIfNeeded(
            target: .tab,
            surfaceIDs: tab.surfaceIDs
        ) else {
            return
        }
        recording.stopIfRecording(tabID: id)
        recordClosedTab(tab)

        do {
            try session.close(tab: id)
            paneLayout.removeZoom(tabID: id)
            scheduledInput.removeScheduledInputs(for: tab.surfaceIDs)
            for surfaceID in tab.surfaceIDs {
                agentEventServer.revoke(surface: surfaceID)
                autocomplete.removeSession(for: surfaceID)
                surfaces.removeValue(forKey: surfaceID)?.removeFromSuperview()
            }
            for browserID in tab.paneIDs
                where !tab.surfaceIDs.contains(browserID) {
                browsers.removeValue(forKey: browserID)?.removeFromSuperview()
            }
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusSelectedSurface()
    }

    func windowDidMove(_ notification: Notification) {
        updateSessionFrame()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        paneLayout.cancelSizeIndicatorHideTask()
        isWindowLiveResizing = true
        paneLayout.updateSizeIndicators()
        paneLayout.setSizeIndicatorsVisible(true)
    }

    func windowDidResize(_ notification: Notification) {
        guard isWindowLiveResizing else { return }
        paneLayout.updateSizeIndicators()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        paneLayout.updateSizeIndicators()
        paneLayout.setSizeIndicatorsVisible(false)
        isWindowLiveResizing = false
        updateSessionFrame()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if bypassNextWindowConfirmation {
            bypassNextWindowConfirmation = false
            return true
        }
        return confirmCloseIfNeeded(
            target: .window,
            surfaceIDs: Array(surfaces.keys)
        )
    }

    func windowWillClose(_ notification: Notification) {
        exitSwapPanesMode()
        if recording.isRecording {
            recording.stop()
        }
        agentStatusPolling.stop()
        agentUsagePolling.stop()
        repositoryStatus.stop()
        paneExplanationTask?.cancel()
        paneExplanationPanel?.close()
        commandSummaryTask?.cancel()
        commandSummaryPanel?.close()
        scheduledInput.removeScheduledInputs(for: Array(surfaces.keys))
        revokeSurfaceCapabilities()
        onWindowClosed(session.id)
    }

    private func configureWindow(_ window: NSWindow) {
        Self.prepareWindowForLiveTransparency(window)
        window.title = ApplicationIdentity.displayName
        titlebarView.update(
            title: ApplicationIdentity.displayName,
            resourceURL: nil
        )
        window.minSize = NSSize(width: 820, height: 400)
        window.delegate = self
        window.tabbingMode = .disallowed

        rebuildChrome()
    }

    static func prepareWindowForLiveTransparency(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    static func installTitlebar(
        _ titlebar: TerminalTitlebarView,
        in window: NSWindow
    ) {
        guard let contentView = window.contentView,
              let frameView = contentView.superview
        else { return }

        window.titleVisibility = .hidden
        titlebar.removeFromSuperview()
        titlebar.contentOverlay.removeFromSuperview()
        let titlebarFrame = NSRect(
            x: 0,
            y: contentView.frame.maxY,
            width: frameView.bounds.width,
            height: max(0, frameView.bounds.maxY - contentView.frame.maxY)
        )
        titlebar.frame = titlebarFrame
        titlebar.autoresizingMask = [.width, .minYMargin]
        titlebar.contentOverlay.frame = titlebarFrame
        titlebar.contentOverlay.autoresizingMask = [.width, .minYMargin]
        frameView.addSubview(titlebar, positioned: .below, relativeTo: nil)
        frameView.addSubview(
            titlebar.contentOverlay,
            positioned: .above,
            relativeTo: nil
        )
    }

    static func prepareSurfaceHostForChrome(_ host: NSView) {
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame.origin = .zero
    }

    static func finalizePaneAttachment(
        in host: NSView,
        redraw: @escaping @MainActor () -> Void,
        restoreFocus: @escaping @MainActor () -> Void = {},
        schedule: (@escaping @MainActor () -> Void) -> Void = { action in
            DispatchQueue.main.async { action() }
        }
    ) {
        host.layoutSubtreeIfNeeded()
        applyPaneRatios(in: host)
        redraw()
        schedule {
            host.layoutSubtreeIfNeeded()
            applyPaneRatios(in: host)
            redraw()
            restoreFocus()
        }
    }

    static func initialSurfaceSize(
        for direction: SplitDirection,
        focusedPaneSize: NSSize,
        dividerThickness: CGFloat = 1
    ) -> NSSize {
        var size = focusedPaneSize
        switch direction {
        case .left, .right:
            size.width = max(
                1,
                (focusedPaneSize.width - dividerThickness) / 2
            )
        case .up, .down:
            size.height = max(
                1,
                (focusedPaneSize.height - dividerThickness) / 2
            )
        }
        return size
    }

    private static func applyPaneRatios(in view: NSView) {
        view.layoutSubtreeIfNeeded()
        if let split = view as? RatioSplitView {
            split.applyCurrentRatio()
        }
        view.subviews.forEach(applyPaneRatios)
    }

    static func claimRender(
        _ tabID: TabID,
        renderedTabID: inout TabID?
    ) -> Bool {
        guard renderedTabID != tabID else { return false }
        renderedTabID = tabID
        return true
    }

    static func shouldCommitFocusChange(
        focused: Bool,
        isAttaching: Bool,
        selectedSurfaceID: TerminalSurfaceID?,
        eventSurfaceID: TerminalSurfaceID
    ) -> Bool {
        focused
            && !isAttaching
            && selectedSurfaceID != eventSurfaceID
    }

    static func makeTopChromeRoot(
        tabs: NSView,
        content: NSView
    ) -> NSView {
        let root = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        for view in [tabs, separator, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: root.topAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 44),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    static func makeBottomChromeRoot(
        tabs: NSView,
        content: NSView
    ) -> NSView {
        let root = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        for view in [tabs, separator, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: tabs.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 44),
        ])
        return root
    }

    static func makeStatusChromeRoot(
        content: NSView,
        statusBar: NSView
    ) -> NSView {
        let root = NSView()
        for view in [content, statusBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
        return root
    }

    static func makeTabPanelSplitItem(
        viewController: NSViewController
    ) -> NSSplitViewItem {
        NSSplitViewItem(viewController: viewController)
    }

    private func rebuildChrome() {
        guard let window else { return }
        surfaceHost.removeFromSuperview()
        Self.prepareSurfaceHostForChrome(surfaceHost)

        let contentController = NSViewController()
        contentController.view = surfaceHost

        let sidebar = TabSidebarView(
            model: sidebarModel,
            attentionCenter: attentionCenter,
            placement: tabPlacement,
            localizer: localizer,
            attentionUnreadOnly: applicationPreferences.attentionUnreadOnly,
            onSelect: { [weak self] id in self?.select(tab: id) },
            onNewTab: { [weak self] in self?.newTab() },
            onClose: { [weak self] id in self?.close(tab: id) },
            onRename: { [weak self] id in self?.rename(tab: id) },
            onCopyPath: { [weak self] id in self?.copyPath(for: id) },
            onRevealInFinder: { [weak self] id in
                self?.revealInFinder(tab: id)
            },
            onMoveUp: { [weak self] id in self?.move(tab: id, offset: -1) },
            onMoveDown: { [weak self] id in self?.move(tab: id, offset: 1) },
            onReorder: { [weak self] source, target in
                self?.reorder(tab: source, to: target)
            },
            onDetachDrag: { [weak self] id in
                self?.tabDrag.beginDrag(for: id)
            },
            onDropTab: { [weak self] index in
                self?.tabDrag.handleDrop(at: index)
            },
            isTabDragActive: { [weak self] in
                self?.tabDrag.isDragActive ?? false
            },
            onEqualizePanes: { [weak self] id in
                self?.equalizePanes(in: id)
            },
            onFocusAttentionItem: { [weak self] item in
                self?.onFocusSurfaceRequested(item.surfaceID)
            },
            onAcknowledgeAttentionItem: { [weak self] item in
                self?.acknowledge(item)
            },
            onAcknowledgeAllAttentionItems: { [weak self] in
                self?.acknowledgeAllAttention()
            },
            onAttentionPopoverDismissed: { [weak self] in
                self?.focusSelectedSurface()
            },
            onSplit: { [weak self] direction in
                self?.splitFocusedPane(direction)
            },
            onClosePane: { [weak self] in self?.closeFocusedPane() },
            onStopRecording: { [weak self] id in
                self?.recording.stopIfRecording(tabID: id)
            }
        )
        let sidebarController = NSHostingController(rootView: sidebar)

        let contentSplitController = NSSplitViewController()
        let contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = 360

        let mainController: NSViewController
        switch tabPlacement {
        case .left:
            if tabPanelsPresented {
                let sidebarItem = Self.makeTabPanelSplitItem(
                    viewController: sidebarController
                )
                sidebarItem.minimumThickness = 180
                sidebarItem.maximumThickness = 280
                sidebarItem.canCollapse = false
                contentSplitController.addSplitViewItem(sidebarItem)
            }
            contentSplitController.addSplitViewItem(contentItem)
            mainController = contentSplitController

        case .right:
            contentSplitController.addSplitViewItem(contentItem)
            if tabPanelsPresented {
                let sidebarItem = Self.makeTabPanelSplitItem(
                    viewController: sidebarController
                )
                sidebarItem.minimumThickness = 180
                sidebarItem.maximumThickness = 280
                sidebarItem.canCollapse = false
                contentSplitController.addSplitViewItem(sidebarItem)
            }
            mainController = contentSplitController

        case .top:
            contentSplitController.addSplitViewItem(contentItem)

            if tabPanelsPresented {
                let rootController = NSViewController()
                rootController.addChild(sidebarController)
                rootController.addChild(contentSplitController)
                rootController.view = Self.makeTopChromeRoot(
                    tabs: sidebarController.view,
                    content: contentSplitController.view
                )
                mainController = rootController
            } else {
                mainController = contentSplitController
            }

        case .bottom:
            contentSplitController.addSplitViewItem(contentItem)

            if tabPanelsPresented {
                let rootController = NSViewController()
                rootController.addChild(sidebarController)
                rootController.addChild(contentSplitController)
                rootController.view = Self.makeBottomChromeRoot(
                    tabs: sidebarController.view,
                    content: contentSplitController.view
                )
                mainController = rootController
            } else {
                mainController = contentSplitController
            }
        }

        let chromeController: NSViewController
        if applicationPreferences.showStatusBar {
            let statusController = NSHostingController(
                rootView: TerminalStatusBarView(
                    model: statusBarModel,
                    revealInFinderTitle: localizer[.revealInFinder],
                    onRevealInFinder: { [weak self] in
                        self?.revealFocusedResourceInFinder()
                    },
                    openRepositoryTitle: localizer[.openOnGitHub],
                    onOpenRepository: { [weak self] in
                        self?.openFocusedRepository()
                    },
                    localizer: localizer,
                    onSelectSleepPreventionMode: { [weak self] mode in
                        self?.onSleepPreventionModeSelected(mode)
                    },
                    onNewScheduledInput: { [weak self] in
                        self?.scheduledInput.newScheduledInput(
                            focusedSurfaceID: self?.session.selectedTab?
                                .focusedSurfaceID
                        )
                    },
                    onEditScheduledInput: { [weak self] schedule in
                        self?.scheduledInput.editScheduledInput(schedule)
                    },
                    onDeleteScheduledInput: { [weak self] schedule in
                        self?.scheduledInput.deleteScheduledInput(schedule)
                    }
                )
            )
            let rootController = NSViewController()
            rootController.addChild(mainController)
            rootController.addChild(statusController)
            rootController.view = Self.makeStatusChromeRoot(
                content: mainController.view,
                statusBar: statusController.view
            )
            chromeController = rootController
        } else {
            chromeController = mainController
        }
        TerminalWindowGeometry.installContentViewController(
            chromeController,
            in: window
        )
        window.contentView?.layoutSubtreeIfNeeded()
        Self.installTitlebar(titlebarView, in: window)

        if tabPanelsPresented {
            switch tabPlacement {
            case .left:
                contentSplitController.splitView.setPosition(
                    220,
                    ofDividerAt: 0
                )
            case .right:
                Self.setRightTabSidebarWidth(
                    220,
                    in: contentSplitController
                )
                DispatchQueue.main.async { [weak contentSplitController] in
                    guard let contentSplitController else { return }
                    Self.setRightTabSidebarWidth(
                        220,
                        in: contentSplitController
                    )
                }
            case .top, .bottom:
                break
            }
        }
    }

    private static func setRightTabSidebarWidth(
        _ width: CGFloat,
        in controller: NSSplitViewController
    ) {
        controller.splitView.layoutSubtreeIfNeeded()
        let visiblePrecedingItems = controller.splitViewItems
            .dropLast()
            .filter { !$0.isCollapsed }
            .count
        let sidebarDivider = max(visiblePrecedingItems - 1, 0)
        let position = controller.splitView.bounds.width - width
        controller.splitView.setPosition(
            position,
            ofDividerAt: sidebarDivider
        )
    }

    private func createInitialSurfaces(
        adopting transfer: TerminalTabTransfer?
    ) throws {
        for tab in session.tabs {
            for state in tab.root.surfaceStates {
                if let surface = transfer?.surfaces[state.id] {
                    surfaces[state.id] = surface
                    bind(surface: surface, to: state.id)
                } else {
                    surfaces[state.id] = try makeSurface(for: state)
                }
            }
            for state in tab.root.browserStates {
                if let browser = transfer?.browsers[state.id] {
                    browsers[state.id] = browser
                    bind(browser: browser, to: state.id)
                } else {
                    browsers[state.id] = makeBrowser(for: state)
                }
            }
        }
    }

    private func observeAttention() {
        attentionObserver = attentionCenter.$items.sink { [weak self] _ in
            self?.refreshPresentation(focusTerminal: false)
        }
    }

    private func updateScheduledInputStatus(
        _ schedules: [PaneInputSchedule]
    ) {
        let focusedID = session.selectedTab?.focusedSurfaceID
        statusBarModel.updateScheduledInputs(
            schedules,
            focusedSurfaceID: focusedID,
            isTerminalPane: focusedID.flatMap { surfaces[$0] } != nil
        )
    }

    private func handleAgentStatusPoll(
        providersChanged: Bool,
        sessionIDsChanged: Bool
    ) {
        let actions = TerminalAgentPollActions.make(
            providersChanged: providersChanged,
            sessionIDsChanged: sessionIDsChanged
        )
        if actions.refreshPresentation {
            refreshSidebarRows()
            updateWindowMetadata()
            updateStatusBar()
        }
        if actions.refreshUsage {
            agentUsagePolling.refreshIfNeeded()
        }
        if providersChanged {
            onAgentActivityChanged()
        }
    }

    /// Ends a run the user interrupted. Providers that fire no hook on
    /// interruption (Claude Code's ESC) would otherwise leave the run
    /// `running` forever — the tab keeps spinning and the Mac keeps itself
    /// awake for an agent that stopped.
    private func handleInterruptedAgentRun(
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        interruption: AgentRunInterruption
    ) {
        let event = AgentHookEventAdapter.interruptionEvent(
            provider: provider,
            runKey: interruption.runKey,
            interruptionKey: interruption.interruptionKey,
            sessionID: attentionCenter.latestRun(
                for: surfaceID,
                provider: provider
            )?.sessionID,
            surfaceID: surfaceID,
            occurredAt: Date()
        )
        guard (try? attentionCenter.append(event)) == true else { return }
        refreshSidebarRows()
        updateStatusBar()
        onAgentActivityChanged()
    }

    private func surfaceWorkingDirectory(
        for surfaceID: TerminalSurfaceID
    ) -> URL? {
        session.tabs
            .first { $0.surfaceIDs.contains(surfaceID) }?
            .root.surfaceState(with: surfaceID)?.workingDirectory
    }

    private func moveOnscreenIfNeeded(_ window: NSWindow) {
        let visible = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersection(window.frame).width >= 80
                && screen.visibleFrame.intersection(window.frame).height >= 80
        }
        guard !visible else { return }

        window.center()
        let frame = window.frame
        session.frame = WindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    private func makeSurface(
        for state: TerminalSurfaceState,
        initialSize: NSSize? = nil,
        initialInput: String? = nil
    ) throws -> GhosttySurfaceView {
        let environment = try agentEventServer.environment(for: state.id)
        let surface: GhosttySurfaceView
        do {
            surface = try GhosttySurfaceView(
                runtime: runtime,
                workingDirectory: state.workingDirectory,
                initialInput: TerminalSurfaceLaunchInput.resolve(
                    spawnInitialInput: initialInput,
                    agentResume: state.agentResume
                ),
                restoredTerminalHistory: state.terminalHistory,
                environmentVariables: environment,
                initialSize: initialSize,
                searchLabels: makeTerminalSearchLabels(),
                contextMenuLabels: makeTerminalContextMenuLabels()
            )
        } catch {
            agentEventServer.revoke(surface: state.id)
            throw error
        }
        bind(surface: surface, to: state.id)
        return surface
    }

    private func bind(
        surface: GhosttySurfaceView,
        to surfaceID: TerminalSurfaceID
    ) {
        surface.onEvent = { [weak self] event in
            self?.handle(event, from: surfaceID)
        }
        surface.onKeyIntercept = { [weak self] event in
            self?.autocomplete.handleKey(event, for: surfaceID) ?? false
        }
        autocomplete.bind(surfaceID: surfaceID)
    }

    private func makeBrowser(for state: BrowserPaneState) -> BrowserPaneView {
        let browser = BrowserPaneView(
            url: state.url,
            closeAccessibilityLabel: localizer[.closeBrowser],
            findLabels: makeBrowserFindLabels(),
            loadFailureMessage: localizer[.browserLoadFailed]
        )
        bind(browser: browser, to: state.id)
        return browser
    }

    private func bind(
        browser: BrowserPaneView,
        to paneID: TerminalSurfaceID
    ) {
        browser.onURLChanged = { [weak self] url in
            guard let self else { return }
            do {
                try self.session.updateBrowserURL(url, for: paneID)
                self.sessionDidChange()
                self.refreshPresentation(focusTerminal: false)
            } catch {
                self.presentActionError(error)
            }
        }
        browser.onFocus = { [weak self] in
            self?.focusBrowserPane(paneID)
        }
        browser.onCommandClickLink = { [weak self] url, sourceView in
            self?.presentLinkMenu(for: url, from: sourceView)
        }
        browser.onClose = { [weak self] in
            self?.closeBrowserPane(paneID)
        }
    }

    private func makeTerminalSearchLabels() -> GhosttySearchLabels {
        GhosttySearchLabels(
            placeholder: localizer[.search],
            previousMatch: localizer[.previousMatch],
            nextMatch: localizer[.nextMatch],
            closeSearch: localizer[.closeSearch]
        )
    }

    private func makeTerminalContextMenuLabels() -> GhosttyContextMenuLabels {
        GhosttyContextMenuLabels(
            copy: localizer[.copy],
            paste: localizer[.paste],
            selectAll: localizer[.selectAll],
            lookUpSelectionFormat: localizer[.lookUpSelectionFormat],
            searchWithGoogle: localizer[.searchWithGoogle],
            share: localizer[.share],
            services: localizer[.services],
            closePane: localizer[.closePane]
        )
    }

    private func makeBrowserFindLabels() -> BrowserFindLabels {
        BrowserFindLabels(
            placeholder: localizer[.search],
            previousMatch: localizer[.previousMatch],
            nextMatch: localizer[.nextMatch],
            closeSearch: localizer[.closeSearch],
            matchFound: localizer[.matchFound],
            noMatches: localizer[.noMatches]
        )
    }

    private func closeBrowserPane(_ paneID: TerminalSurfaceID) {
        closePaneOrContainingTab(paneID)
    }

    private func closePaneOrContainingTab(
        _ paneID: TerminalSurfaceID,
        requiresConfirmation: Bool = true
    ) {
        guard let tab = session.tabs.first(where: {
            $0.paneIDs.contains(paneID)
        }) else { return }

        switch TerminalPaneCloseAction.make(
            paneCount: tab.paneIDs.count,
            tabCount: session.tabs.count
        ) {
        case .closePane:
            closePane(paneID, requiresConfirmation: requiresConfirmation)
        case .closeTab:
            close(tab: tab.id, requiresConfirmation: requiresConfirmation)
        case .closeLastPane:
            closeLastPane(in: tab)
        }
    }

    private func focusBrowserPane(_ id: TerminalSurfaceID) {
        guard session.selectedTab?.focusedSurfaceID != id else { return }
        do {
            try session.focus(pane: id)
            sessionDidChange()
            refreshPresentation(focusTerminal: false)
            acknowledgeAttention(for: id)
        } catch {
            presentActionError(error)
        }
    }

    private func revokeSurfaceCapabilities() {
        for surfaceID in surfaces.keys {
            agentEventServer.revoke(surface: surfaceID)
        }
    }

    private func handle(
        _ event: GhosttySurfaceEvent,
        from surfaceID: TerminalSurfaceID
    ) {
        switch event {
        case .titleChanged:
            break

        case let .workingDirectoryChanged(url):
            do {
                try session.updateWorkingDirectory(url, for: surfaceID)
                sessionDidChange()
                refreshPresentation(focusTerminal: false)
            } catch {
                presentActionError(error)
            }

        case .closePaneRequested:
            // Context-menu close: same flow as the Close Pane command
            // (confirmation included), aimed at the clicked pane.
            closePaneOrContainingTab(surfaceID)

        case let .closeRequested(processAlive):
            guard let tab = session.tabs.first(where: {
                $0.surfaceIDs.contains(surfaceID)
            }) else { return }
            switch TerminalExitCloseAction.make(
                processAlive: processAlive,
                paneCount: tab.paneIDs.count,
                tabCount: session.tabs.count
            ) {
            case .ignore:
                break
            case let .closePane(requiresConfirmation):
                handleExitedSurfaceClose(
                    surfaceID,
                    requiresConfirmation: requiresConfirmation,
                    confirmation: { [self] in
                        confirmCloseIfNeeded(
                            target: .pane,
                            surfaceIDs: [surfaceID]
                        )
                    },
                    close: { [self] in
                        closePane(surfaceID, requiresConfirmation: false)
                    }
                )
            case let .closeTab(requiresConfirmation):
                handleExitedSurfaceClose(
                    surfaceID,
                    requiresConfirmation: requiresConfirmation,
                    confirmation: { [self] in
                        confirmCloseIfNeeded(
                            target: .tab,
                            surfaceIDs: tab.surfaceIDs
                        )
                    },
                    close: { [self] in
                        close(tab: tab.id, requiresConfirmation: false)
                    }
                )
            case .closeLastPane:
                handleExitedSurfaceClose(
                    surfaceID,
                    requiresConfirmation:
                        applicationPreferences.confirmClosingLastPane,
                    confirmation: { [self] in
                        confirmClosingLastPaneIfNeeded(
                            surfaceIDs: tab.surfaceIDs
                        )
                    },
                    close: { [self] in
                        close(tab: tab.id, requiresConfirmation: false)
                    }
                )
            }

        case .newTabRequested:
            newTab()

        case .closeTabRequested:
            if let tabID = tabID(containing: surfaceID) {
                close(tab: tabID)
            }

        case .newWindowRequested:
            onNewWindowRequested(currentWorkingDirectory)

        case .closeWindowRequested:
            window?.performClose(nil)

        case let .openURLRequested(url):
            guard let surface = surfaces[surfaceID] else { return }
            let resolved = BrowserAddress.resolveLink(
                url,
                workingDirectory: workingDirectory(forPane: surfaceID)
            )
            presentLinkMenu(for: resolved, from: surface)

        case .cellSizeChanged:
            updateStatusBar()

        case let .commandFinished(exitCode, _):
            lastCommandResultBySurface[surfaceID] = LastCommandResult(
                exitCode: exitCode,
                finishedAt: Date()
            )
            autocomplete.handleCommandFinished(
                exitCode: exitCode,
                surfaceID: surfaceID
            )

        case .rendererHealthChanged,
             .childExited:
            break

        case let .focusChanged(focused):
            guard Self.shouldCommitFocusChange(
                focused: focused,
                isAttaching: isAttachingSelectedTab,
                selectedSurfaceID: session.selectedTab?.focusedSurfaceID,
                eventSurfaceID: surfaceID
            )
            else { return }
            do {
                try session.focus(surface: surfaceID)
                sessionDidChange()
                refreshPresentation(focusTerminal: false)
                acknowledgeAttention(for: surfaceID)
            } catch {
                presentActionError(error)
            }
        }
    }

    private func refreshPresentation(focusTerminal: Bool) {
        if let tab = session.selectedTab {
            paneLayout.synchronizeZoom(with: tab)
        }
        agentStatusPolling.refreshProviders()
        refreshSidebarRows()

        attachSelectedTab()
        paneLayout.updateFocus(focusedID: session.selectedTab?.focusedSurfaceID)
        updateWindowMetadata()
        updateStatusBar()
        repositoryStatus.refreshIfNeeded()
        agentUsagePolling.refreshIfNeeded()
        if focusTerminal {
            focusSelectedSurface()
        }
        onAgentActivityChanged()
    }

    private func refreshSidebarRows() {
        let lifecycleBySurface = agentLifecycleBySurface
        sidebarModel.rows = session.tabs.enumerated().map { offset, tab in
            let state = tab.root.surfaceState(with: tab.focusedSurfaceID)
            let browser = tab.root.browserState(with: tab.focusedSurfaceID)
            let title = displayTitle(for: tab)
            return TabSidebarRow(
                id: tab.id,
                title: title,
                paneCount: tab.paneIDs.count,
                attentionCount: attentionCenter.actionableCount(
                    for: tab.surfaceIDs
                ),
                hasRunningAgent: TerminalTabAgentActivity.isProcessing(
                    surfaceIDs: tab.surfaceIDs,
                    foregroundProvidersBySurface: agentStatusPolling.providersBySurface,
                    lifecycleBySurface: lifecycleBySurface
                ),
                isRecording: recording.isRecording(tabID: tab.id),
                hasCollapsedPanes: paneLayout.zoomTarget(for: tab) != nil,
                resourceURL: state?.workingDirectory ?? browser?.url,
                number: offset + 1
            )
        }
        sidebarModel.selectedTabID = session.selectedTabID
        sidebarModel.actionableAttentionCount = attentionCenter.actionableCount
    }

    private var agentLifecycleBySurface: [
        TerminalSurfaceID: TerminalAgentLifecycle
    ] {
        agentStatusPolling.providersBySurface.reduce(
            into: [TerminalSurfaceID: TerminalAgentLifecycle]()
        ) { result, entry in
            guard let run = attentionCenter.latestRun(
                for: entry.key,
                provider: entry.value
            ) else { return }
            result[entry.key] = TerminalAgentLifecycle(
                provider: run.provider,
                state: run.state
            )
        }
    }

    private func presentLinkMenu(for url: URL, from sourceView: NSView) {
        pendingLinkURL = url
        defer { pendingLinkURL = nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, destination) in LinkOpenDestination.allCases.enumerated() {
            let item = menu.addItem(
                withTitle: linkMenuTitle(for: destination),
                action: #selector(openPendingLink(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
        }

        let position: NSPoint
        if let event = NSApplication.shared.currentEvent,
           event.window === sourceView.window {
            position = sourceView.convert(event.locationInWindow, from: nil)
        } else {
            position = NSPoint(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY
            )
        }
        menu.popUp(positioning: nil, at: position, in: sourceView)
    }

    private func linkMenuTitle(for destination: LinkOpenDestination) -> String {
        switch destination {
        case .externalBrowser: localizer[.openInBrowser]
        case .newTab: localizer[.openInNewTab]
        case .newPaneRight: localizer[.openInNewPaneRight]
        case .newPaneDown: localizer[.openInNewPaneDown]
        case .copyLink: localizer[.copyLink]
        }
    }

    @objc private func openPendingLink(_ sender: NSMenuItem) {
        guard let url = pendingLinkURL,
              LinkOpenDestination.allCases.indices.contains(sender.tag)
        else { return }
        switch LinkOpenDestination.allCases[sender.tag] {
        case .externalBrowser:
            NSWorkspace.shared.open(url)
        case .newTab:
            openBrowserTab(url)
        case .newPaneRight:
            openBrowserPane(url, direction: .right)
        case .newPaneDown:
            openBrowserPane(url, direction: .down)
        case .copyLink:
            LinkClipboard.copy(url)
        }
    }

    private func attachSelectedTab() {
        guard let tab = session.selectedTab else { return }
        let requiresFullRender = Self.claimRender(
            tab.id,
            renderedTabID: &renderedTabID
        )
        isAttachingSelectedTab = true
        defer { isAttachingSelectedTab = false }

        if requiresFullRender {
            paneLayout.dismissZoomPresentation()
            for surface in surfaces.values
                where surface.isDescendant(of: surfaceHost) {
                surface.removeFromSuperview()
            }
            surfaceHost.subviews.forEach { $0.removeFromSuperview() }
            paneLayout.resetHosts()
            guard let rootView = paneLayout.makeSplitView(tab.root, path: []) else {
                renderedTabID = nil
                return
            }
            rootView.translatesAutoresizingMaskIntoConstraints = false
            surfaceHost.addSubview(rootView)
            NSLayoutConstraint.activate([
                rootView.leadingAnchor.constraint(
                    equalTo: surfaceHost.leadingAnchor
                ),
                rootView.trailingAnchor.constraint(
                    equalTo: surfaceHost.trailingAnchor
                ),
                rootView.topAnchor.constraint(equalTo: surfaceHost.topAnchor),
                rootView.bottomAnchor.constraint(
                    equalTo: surfaceHost.bottomAnchor
                ),
            ])
        }

        let zoomChanged = paneLayout.updateZoomPresentation(for: tab)
        guard requiresFullRender || zoomChanged else { return }
        Self.finalizePaneAttachment(
            in: surfaceHost,
            redraw: { [weak self] in
                guard let self else { return }
                for surface in surfaces.values
                    where surface.isDescendant(of: surfaceHost) {
                    surface.drawImmediately()
                }
            },
            restoreFocus: { [weak self] in
                self?.focusSelectedSurface()
            }
        )
    }

    private func focusSelectedSurface() {
        guard let tab = session.selectedTab else { return }
        if let surface = surfaces[tab.focusedSurfaceID] {
            window?.makeFirstResponder(surface)
        } else {
            browsers[tab.focusedSurfaceID]?.focusContent()
        }
        acknowledgeAttention(for: tab.focusedSurfaceID)
    }

    private func acknowledgeAttention(for surfaceID: TerminalSurfaceID) {
        do {
            let acknowledgedCount = try attentionCenter
                .acknowledgeActionableItems(for: surfaceID)
            if acknowledgedCount > 0 {
                refreshSidebarRows()
            }
        } catch {
            presentActionError(error)
        }
    }

    private func rename(tab id: TabID) {
        guard let tab = session.tabs.first(where: { $0.id == id }) else {
            return
        }
        let alert = Self.makeRenameTabAlert(
            currentTitle: tab.pinnedTitle ?? displayTitle(for: tab),
            localizer: localizer,
            suggestName: tabNameSuggestionProvider(for: tab)
        )
        guard let textField = Self.renameTabTextField(in: alert) else {
            return
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try session.rename(tab: id, title: textField.stringValue)
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    /// On-device tab-name suggestion needs macOS 26 (Foundation Models),
    /// an available system model, and a terminal pane to read; otherwise
    /// the rename alert shows no Auto-Name button.
    private func tabNameSuggestionProvider(
        for tab: TabSession
    ) -> TabNameSuggestionRequest? {
        guard #available(macOS 26, *), TabNameSuggester.isAvailable,
              let surface = surfaces[tab.focusedSurfaceID]
        else { return nil }
        let language = applicationPreferences.language.resolved()
        return TabNameSuggestionRequest(
            captureBuffer: { [weak surface] in surface?.screenText() },
            suggest: { buffer in
                await TabNameSuggester.suggest(
                    buffer: buffer,
                    language: language
                )
            }
        )
    }

    static func makeRenameTabAlert(
        currentTitle: String,
        localizer: MyTTYLocalizer,
        suggestName: TabNameSuggestionRequest? = nil
    ) -> NSAlert {
        let alert = ApplicationAlert.make()
        alert.messageText = localizer[.renameTab]
        let textField = NSTextField(string: currentTitle)
        textField.placeholderString = localizer[.tabName]
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        if let suggestName {
            alert.accessoryView = TabNameSuggestAccessoryView(
                textField: textField,
                buttonTitle: localizer[.autoNameTab],
                request: suggestName
            )
        } else {
            alert.accessoryView = textField
        }
        alert.addButton(withTitle: localizer[.save])
        alert.addButton(withTitle: localizer[.cancel])
        alert.window.initialFirstResponder = textField
        return alert
    }

    static func renameTabTextField(in alert: NSAlert) -> NSTextField? {
        switch alert.accessoryView {
        case let field as NSTextField: field
        case let accessory as TabNameSuggestAccessoryView: accessory.textField
        default: nil
        }
    }

    private func copyPath(for id: TabID) {
        guard let tab = session.tabs.first(where: { $0.id == id }),
              let url = resourceURL(for: tab)
        else { return }
        let value = url.isFileURL ? url.path : url.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func revealInFinder(tab id: TabID) {
        guard let tab = session.tabs.first(where: { $0.id == id }),
              let url = resourceURL(for: tab),
              url.isFileURL
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealFocusedResourceInFinder() {
        revealInFinder(tab: session.selectedTabID)
    }

    private func move(tab id: TabID, offset: Int) {
        guard let index = session.tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destination = index + offset
        guard session.tabs.indices.contains(destination) else { return }
        performTabMove(id, to: destination)
    }

    private func reorder(tab id: TabID, to targetID: TabID) {
        guard let destination = session.tabs.firstIndex(where: {
            $0.id == targetID
        }) else { return }
        performTabMove(id, to: destination)
    }

    private func performTabMove(_ id: TabID, to destination: Int) {
        do {
            try session.move(tab: id, to: destination)
            sessionDidChange()
            refreshPresentation(focusTerminal: false)
        } catch {
            presentActionError(error)
        }
    }

    /// Detaches a tab together with its live pane views so another
    /// window can adopt it. Closes this window when its last tab left.
    func beginTabTransfer(_ id: TabID) -> TerminalTabTransfer? {
        guard session.tabs.contains(where: { $0.id == id }) else {
            return nil
        }
        recording.stopIfRecording(tabID: id)
        let tab: TabSession
        do {
            tab = try session.detach(tab: id)
        } catch {
            presentActionError(error)
            return nil
        }
        paneLayout.removeZoom(tabID: id)
        var movedSurfaces: [TerminalSurfaceID: GhosttySurfaceView] = [:]
        var movedBrowsers: [TerminalSurfaceID: BrowserPaneView] = [:]
        for paneID in tab.paneIDs {
            if let surface = surfaces.removeValue(forKey: paneID) {
                surface.onEvent = nil
                surface.onKeyIntercept = nil
                autocomplete.removeSession(for: paneID)
                movedSurfaces[paneID] = surface
            }
            if let browser = browsers.removeValue(forKey: paneID) {
                movedBrowsers[paneID] = browser
            }
        }
        renderedTabID = nil
        if session.tabs.isEmpty {
            bypassNextWindowConfirmation = true
            DispatchQueue.main.async { [weak self] in
                self?.window?.performClose(nil)
            }
        } else {
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        }
        return TerminalTabTransfer(
            tab: tab,
            surfaces: movedSurfaces,
            browsers: movedBrowsers
        )
    }

    func adopt(_ transfer: TerminalTabTransfer, at insertionIndex: Int) {
        let index = min(max(insertionIndex, 0), session.tabs.count)
        do {
            try session.insert(tab: transfer.tab, at: index, select: true)
        } catch {
            presentActionError(error)
            return
        }
        for (surfaceID, surface) in transfer.surfaces {
            surfaces[surfaceID] = surface
            bind(surface: surface, to: surfaceID)
            surface.updateSearchLabels(makeTerminalSearchLabels())
            surface.updateContextMenuLabels(makeTerminalContextMenuLabels())
        }
        for (paneID, browser) in transfer.browsers {
            browsers[paneID] = browser
            bind(browser: browser, to: paneID)
            browser.updateFindLabels(makeBrowserFindLabels())
        }
        renderedTabID = nil
        sessionDidChange()
        refreshPresentation(focusTerminal: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func resourceURL(for tab: TabSession) -> URL? {
        tab.root.surfaceState(with: tab.focusedSurfaceID)?.workingDirectory
            ?? tab.root.browserState(with: tab.focusedSurfaceID)?.url
    }

    private func displayTitle(for tab: TabSession) -> String {
        return tab.pinnedTitle
            ?? TerminalTabTitle.defaultTitle(
                for: tab,
                localizer: localizer
            )
    }

    /// The display title of the tab containing `surfaceID`, for
    /// attention notifications to show which tab an agent needs the user
    /// in. `nil` when this window has no tab for that surface (it belongs
    /// to another window, or has since closed).
    func tabTitle(for surfaceID: TerminalSurfaceID) -> String? {
        guard let tab = session.tabs.first(where: {
            $0.surfaceIDs.contains(surfaceID)
        }) else { return nil }
        return displayTitle(for: tab)
    }

    private func acknowledge(_ item: AttentionItem) {
        do {
            try attentionCenter.acknowledge(item)
        } catch {
            presentActionError(error)
        }
    }

    private func acknowledgeAllAttention() {
        do {
            let acknowledgedCount = try attentionCenter
                .acknowledgeAllActionableItems()
            if acknowledgedCount > 0 {
                refreshSidebarRows()
            }
        } catch {
            presentActionError(error)
        }
    }

    private func updateWindowMetadata() {
        guard let tab = session.selectedTab else {
            window?.title = ApplicationIdentity.displayName
            window?.representedURL = nil
            titlebarView.update(
                title: ApplicationIdentity.displayName,
                resourceURL: nil
            )
            return
        }
        let title = TerminalWindowTitle.make(
            baseTitle: displayTitle(for: tab),
            activeProvider: foregroundAgentProvider
        )
        let resourceURL = resourceURL(for: tab)
        window?.title = title
        window?.representedURL = resourceURL
        titlebarView.update(title: title, resourceURL: resourceURL)
    }

    private func updateStatusBar() {
        guard let tab = session.selectedTab else {
            statusBarModel.content = TerminalStatusBarContent(
                sleepStatus: agentSleepStatus
            )
            statusBarModel.updateScheduledInputs(
                [],
                focusedSurfaceID: nil,
                isTerminalPane: false
            )
            return
        }

        let focusedID = tab.focusedSurfaceID
        let resourceURL = resourceURL(for: tab)
        let resource = resourceURL.map {
            $0.isFileURL
                ? ($0.path as NSString).abbreviatingWithTildeInPath
                : $0.absoluteString
        } ?? ""
        let browser = tab.root.browserState(with: focusedID)
        let resourceSymbolName = browser.map {
            $0.url.isFileURL ? "doc.richtext" : "globe"
        } ?? "folder"
        let agent = TerminalAgentDisplay.resolve(
            foregroundProvider: foregroundAgentProvider
        )
        let activeAgentSessionID: String?
        if let provider = foregroundAgentProvider {
            activeAgentSessionID = agentSessionID(
                for: focusedID,
                provider: provider,
                processBound: agentStatusPolling.sessionIDsBySurface[focusedID]
            )
        } else {
            activeAgentSessionID = nil
        }
        let agentUsage = AgentUsageStatusSelection.content(
            activeProvider: foregroundAgentProvider,
            loadedProvider: agentUsagePolling.loadedProvider,
            summary: agentUsagePolling.loadedSummary
        )
        let agentSessionStatus = agentStatusPolling.statusBySurface[focusedID]
        statusBarModel.content = TerminalStatusBarContent(
            resource: resource,
            resourceSymbolName: resourceSymbolName,
            canRevealInFinder: resourceURL?.isFileURL == true,
            repositoryURL: activeRepositoryStatus?.pageURL,
            branchName: activeRepositoryStatus?.branchName,
            agentName: agent.map { TerminalWindowTitle.name(for: $0.provider) },
            agentSessionID: activeAgentSessionID,
            agentModelName: agentSessionStatus?.modelName,
            agentUsage: agentUsage,
            agentContext: agentSessionStatus?.contextRemainingPercent.map {
                AgentUsageMeterContent(
                    title: localizer[.context],
                    remainingPercent: $0
                )
            },
            sleepStatus: agentSleepStatus
        )
        statusBarModel.updateScheduledInputs(
            scheduledInput.schedules,
            focusedSurfaceID: focusedID,
            isTerminalPane: surfaces[focusedID] != nil
        )
    }

    private func agentSessionID(
        for surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        processBound: String?
    ) -> String? {
        AgentSessionIDSelection.resolve(
            processBound: processBound,
            hook: attentionCenter.latestRun(
                for: surfaceID,
                provider: provider
            )?.sessionID
        )
    }

    private func activeAgentResume(
        for surfaceID: TerminalSurfaceID
    ) -> AgentResumeDescriptor? {
        guard let surface = surfaces[surfaceID] else { return nil }
        let processID = surface.foregroundProcessID
        guard let provider = TerminalAgentProcessDetector.provider(
            processID: processID
        ),
        let kind = TerminalAgentProcessDetector.resumeKind(
            processID: processID
        ),
        let sessionID = agentSessionID(
            for: surfaceID,
            provider: provider,
            processBound: provider == .codex
                ? CodexSessionInspector.sessionID(processID: processID)
                : nil
        )
        else { return nil }
        return AgentResumeDescriptor(kind: kind, sessionID: sessionID)
    }

    private var activeRepositoryStatus: GitHubRepositoryStatus? {
        repositoryStatus.status(for: focusedTerminalDirectory)
    }

    private var focusedTerminalDirectory: URL? {
        guard let tab = session.selectedTab else { return nil }
        let focusedID = tab.focusedSurfaceID
        if agentStatusPolling.foregroundProvider(for: focusedID) != nil,
           let processID = surfaces[focusedID]?.foregroundProcessID,
           let agentDirectory = TerminalAgentProcessDetector.workingDirectory(
               processID: processID
           ) {
            return agentDirectory.standardizedFileURL
        }
        return tab.root.surfaceState(with: focusedID)?
            .workingDirectory.standardizedFileURL
    }

    private func openFocusedRepository() {
        guard let url = activeRepositoryStatus?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func deliverScheduledInput(_ schedule: PaneInputSchedule) -> Bool {
        scheduledInput.deliverScheduledInput(schedule)
    }

    func remotePaneContent(
        forPane paneID: TerminalSurfaceID
    ) -> RemotePaneContent? {
        remotePane.content(forPane: paneID)
    }

    @discardableResult
    func deliverRemoteInput(
        paneID: TerminalSurfaceID,
        text: String,
        pressEnter: Bool
    ) -> Bool {
        remotePane.deliverInput(
            paneID: paneID,
            text: text,
            pressEnter: pressEnter
        )
    }

    @discardableResult
    func deliverRemoteKey(
        paneID: TerminalSurfaceID,
        event: RemoteKeyMapping.KeyEvent
    ) -> Bool {
        remotePane.deliverKey(paneID: paneID, event: event)
    }

    @discardableResult
    func deliverRemoteScroll(
        paneID: TerminalSurfaceID,
        deltaY: Double
    ) -> Bool {
        remotePane.deliverScroll(paneID: paneID, deltaY: deltaY)
    }

    /// The working directory `mytty-ctl list` reports for a pane; nil for
    /// browser panes and for panes this controller doesn't own.
    func workingDirectory(forPane paneID: TerminalSurfaceID) -> URL? {
        guard let tab = session.tabs.first(where: {
            $0.paneIDs.contains(paneID)
        }) else { return nil }
        return tab.root.surfaceState(with: paneID)?.workingDirectory
    }

    /// The executable path and argv of a pane's foreground process, for
    /// `mytty-ctl agent spawn --access inherit`: it reads the anchor
    /// pane's own foreground process (the lead agent) to detect its
    /// provider and copy its mode flags onto a newly spawned worker. Nil
    /// for panes this controller doesn't own or whose foreground process
    /// can't be resolved.
    func foregroundProcessInvocation(
        forPane paneID: TerminalSurfaceID
    ) -> (executablePath: String, arguments: [String])? {
        guard let surface = surfaces[paneID] else { return nil }
        return TerminalAgentProcessDetector.invocation(
            processID: surface.foregroundProcessID
        )
    }

    /// Closes a pane on behalf of `mytty-ctl close-pane`, skipping the
    /// interactive "close pane with a running agent?" confirmation dialog
    /// that `closeFocusedPane()` shows for human-driven closes — an AI
    /// orchestrator has no dialog to answer and would hang forever.
    @discardableResult
    func closePane(forControl paneID: TerminalSurfaceID) -> Bool {
        guard session.tabs.contains(where: {
            $0.paneIDs.contains(paneID)
        }) else { return false }
        closePaneOrContainingTab(paneID, requiresConfirmation: false)
        return true
    }

    private func updateSessionFrame() {
        guard let frame = window?.frame else { return }
        session.frame = WindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
        sessionDidChange()
    }

    private func sessionDidChange() {
        onSessionChanged(session)
    }

    private func closePane(
        _ paneID: TerminalSurfaceID,
        requiresConfirmation: Bool = true
    ) {
        guard !requiresConfirmation || confirmCloseIfNeeded(
            target: .pane,
            surfaceIDs: surfaces[paneID] == nil ? [] : [paneID]
        ) else { return }
        recording.stopIfRecording(surfaceID: paneID)
        recordClosedPane(paneID)
        do {
            try session.closePane(paneID)
            scheduledInput.removeScheduledInputs(for: [paneID])
            if surfaces[paneID] != nil {
                agentEventServer.revoke(surface: paneID)
            }
            autocomplete.removeSession(for: paneID)
            surfaces.removeValue(forKey: paneID)?.removeFromSuperview()
            browsers.removeValue(forKey: paneID)?.removeFromSuperview()
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }

    private func closeLastPane(in tab: TabSession) {
        guard confirmClosingLastPaneIfNeeded(
            surfaceIDs: tab.surfaceIDs
        ) else { return }
        close(tab: tab.id, requiresConfirmation: false)
    }

    private func recordClosedPane(_ paneID: TerminalSurfaceID) {
        guard let tab = session.tabs.first(where: {
            $0.paneIDs.contains(paneID)
        }) else { return }
        if let surface = surfaces[paneID] {
            guard var state = tab.root.surfaceState(with: paneID)
            else { return }
            state.terminalHistory = TerminalHistory.bounded(
                TerminalHistory.sanitized(surface.screenVTText())
            )
            state.agentResume = activeAgentResume(for: paneID)
            closedPaneHistory.push(.terminal(state))
        } else if let browserState = tab.root.browserState(with: paneID) {
            closedPaneHistory.push(.browser(browserState))
        }
    }

    private func recordClosedTab(_ tab: TabSession) {
        var recorded = tab
        for surfaceID in tab.surfaceIDs {
            let history = TerminalHistory.bounded(
                TerminalHistory.sanitized(
                    surfaces[surfaceID]?.screenVTText() ?? ""
                )
            )
            try? recorded.updateTerminalHistory(history, for: surfaceID)
            try? recorded.updateAgentResume(
                activeAgentResume(for: surfaceID),
                for: surfaceID
            )
        }
        closedPaneHistory.push(.tab(recorded))
    }

    func reopenMostRecentClosed() {
        guard let entry = closedPaneHistory.entries.first else { return }
        reopen(entry)
    }

    func reopen(entryID: UUID) {
        guard let entry = closedPaneHistory.entries.first(where: {
            $0.id == entryID
        }) else { return }
        reopen(entry)
    }

    private func reopen(_ entry: ClosedPaneHistoryEntry) {
        switch entry.record {
        case let .terminal(state):
            reopenTerminal(state, entryID: entry.id)
        case let .browser(state):
            reopenBrowser(state, entryID: entry.id)
        case let .tab(tab):
            reopenTab(tab, entryID: entry.id)
        }
    }

    private func reopenTerminal(
        _ state: TerminalSurfaceState,
        entryID: UUID
    ) {
        let restored = state.regeneratingID()
        do {
            let surface = try makeSurface(for: restored)
            do {
                try session.splitFocusedSurface(
                    adding: restored,
                    direction: .right
                )
            } catch {
                agentEventServer.revoke(surface: restored.id)
                autocomplete.removeSession(for: restored.id)
                throw error
            }
            surfaces[restored.id] = surface
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            closedPaneHistory.remove(id: entryID)
        } catch {
            presentActionError(error)
        }
    }

    private func reopenBrowser(
        _ state: BrowserPaneState,
        entryID: UUID
    ) {
        let restored = state.regeneratingID()
        do {
            let browser = makeBrowser(for: restored)
            try session.splitFocusedBrowser(
                adding: restored,
                direction: .right
            )
            browsers[restored.id] = browser
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            closedPaneHistory.remove(id: entryID)
        } catch {
            presentActionError(error)
        }
    }

    private func reopenTab(_ tab: TabSession, entryID: UUID) {
        let restored = tab.regeneratingIDs()
        var createdSurfaceIDs: [TerminalSurfaceID] = []
        do {
            try session.add(tab: restored, select: true)
            do {
                for state in restored.root.surfaceStates {
                    let surface = try makeSurface(for: state)
                    surfaces[state.id] = surface
                    createdSurfaceIDs.append(state.id)
                }
                for state in restored.root.browserStates {
                    browsers[state.id] = makeBrowser(for: state)
                }
            } catch {
                for surfaceID in createdSurfaceIDs {
                    agentEventServer.revoke(surface: surfaceID)
                    autocomplete.removeSession(for: surfaceID)
                    surfaces.removeValue(forKey: surfaceID)?
                        .removeFromSuperview()
                }
                try? session.close(tab: restored.id)
                throw error
            }
            renderedTabID = nil
            sessionDidChange()
            refreshPresentation(focusTerminal: true)
            closedPaneHistory.remove(id: entryID)
        } catch {
            presentActionError(error)
        }
    }

    private func handleExitedSurfaceClose(
        _ surfaceID: TerminalSurfaceID,
        requiresConfirmation: Bool,
        confirmation: () -> Bool,
        close: () -> Void
    ) {
        let confirmed = !requiresConfirmation || confirmation()
        switch TerminalExitedSurfaceCloseResolution.make(
            requiresConfirmation: requiresConfirmation,
            confirmed: confirmed
        ) {
        case .close:
            close()
        case .restartSurface:
            restartExitedSurface(surfaceID)
        }
    }

    private func restartExitedSurface(_ surfaceID: TerminalSurfaceID) {
        guard let state = session.tabs.lazy.compactMap({
            $0.root.surfaceState(with: surfaceID)
        }).first,
        let exitedSurface = surfaces[surfaceID]
        else { return }

        let initialSize = exitedSurface.bounds.width > 0
                && exitedSurface.bounds.height > 0
            ? exitedSurface.bounds.size
            : nil
        exitedSurface.onEvent = nil
        exitedSurface.onKeyIntercept = nil
        agentEventServer.revoke(surface: surfaceID)
        autocomplete.removeSession(for: surfaceID)

        do {
            let replacement = try makeSurface(
                for: state,
                initialSize: initialSize
            )
            surfaces[surfaceID] = replacement
            exitedSurface.removeFromSuperview()
            renderedTabID = nil
            refreshPresentation(focusTerminal: true)
        } catch {
            presentActionError(error)
        }
    }


    private func tabID(containing surfaceID: TerminalSurfaceID) -> TabID? {
        session.tabs.first { $0.surfaceIDs.contains(surfaceID) }?.id
    }

    private func confirmCloseIfNeeded(
        target: TerminalCloseTarget,
        surfaceIDs: [TerminalSurfaceID]
    ) -> Bool {
        let hasRunningProcess = surfaceIDs.contains {
            surfaces[$0]?.needsConfirmQuit == true
        }
        let confirmation = applicationPreferences.confirmation(for: target)
        guard confirmation.requiresConfirmation(
            hasRunningProcess: hasRunningProcess
        ) else { return true }

        let alert = Self.makeCloseConfirmationAlert(
            target: target,
            hasRunningProcess: hasRunningProcess,
            localizer: localizer
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func makeCloseConfirmationAlert(
        target: TerminalCloseTarget,
        hasRunningProcess: Bool,
        localizer: MyTTYLocalizer
    ) -> NSAlert {
        let alert = ApplicationAlert.make(style: .warning)
        switch target {
        case .window:
            alert.messageText = localizer[.closeWindowQuestion]
        case .pane:
            alert.messageText = localizer[.closePaneQuestion]
        case .tab:
            alert.messageText = localizer[.closeTabQuestion]
        }
        alert.informativeText = hasRunningProcess
            ? localizer[.runningProcessWarning]
            : ""
        alert.addButton(withTitle: localizer[.close])
        alert.addButton(withTitle: localizer[.cancel])
        return alert
    }

    private func confirmClosingLastPaneIfNeeded(
        surfaceIDs: [TerminalSurfaceID]
    ) -> Bool {
        guard applicationPreferences.confirmClosingLastPane else {
            return true
        }
        let hasRunningProcess = surfaceIDs.contains {
            surfaces[$0]?.needsConfirmQuit == true
        }
        let alert = Self.makeLastPaneCloseConfirmationAlert(
            hasRunningProcess: hasRunningProcess,
            localizer: localizer
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func makeLastPaneCloseConfirmationAlert(
        hasRunningProcess: Bool,
        localizer: MyTTYLocalizer
    ) -> NSAlert {
        let alert = ApplicationAlert.make(style: .warning)
        alert.messageText = localizer[.closeLastPaneQuestion]
        var details = [localizer[.closeLastPaneWarning]]
        if hasRunningProcess {
            details.append(localizer[.runningProcessWarning])
        }
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: localizer[.close])
        alert.addButton(withTitle: localizer[.cancel])
        return alert
    }

    private func presentActionError(_ error: Error) {
        let alert = ApplicationAlert.make(style: .critical)
        alert.messageText = localizer[.couldNotCompleteAction]
        alert.informativeText = String(describing: error)
        alert.runModal()
    }
}

private extension SplitNode {
    var surfaceStates: [TerminalSurfaceState] {
        switch self {
        case let .surface(state):
            [state]
        case .browser:
            []
        case let .split(_, _, first, second):
            first.surfaceStates + second.surfaceStates
        }
    }

    var browserStates: [BrowserPaneState] {
        switch self {
        case .surface:
            []
        case let .browser(state):
            [state]
        case let .split(_, _, first, second):
            first.browserStates + second.browserStates
        }
    }

    func surfaceState(
        with id: TerminalSurfaceID
    ) -> TerminalSurfaceState? {
        switch self {
        case let .surface(state):
            state.id == id ? state : nil
        case .browser:
            nil
        case let .split(_, _, first, second):
            first.surfaceState(with: id) ?? second.surfaceState(with: id)
        }
    }
}
