import AppKit
import GhosttyAdapter
import MyTTYCore

/// Owns the terminal window lifecycle: creating/removing `TerminalWindowController`
/// instances, tab drag-and-drop transfer between windows, session
/// persistence/restoration, and window-frame placement math.
///
/// `AppDelegate` remains the owner of the shared engine objects (Ghostty
/// runtime, attention center, agent event server, settings model); it hands
/// them to this coordinator once each is constructed during launch, and this
/// coordinator uses them only to build `TerminalWindowController` instances.
/// Callbacks that need AppDelegate-owned UI state (agent sleep prevention,
/// error alerts, the settings window, the remote access broadcast) are
/// injected as closures at init time, matching the existing callback-heavy
/// style used elsewhere in this file (e.g. `AgentEventServer`, `PaneInputScheduler`).
@MainActor
final class WindowSessionCoordinator {
    private(set) var controllers: [TerminalWindowController] = []
    private let tabDragCoordinator = TabDragCoordinator()
    let closedPaneHistory = ClosedPaneHistory()
    var isRestoringSessions = false
    private var terminationState = ApplicationTerminationState()
    var rememberedWindowFrame: WindowFrame?
    private var sessionRepository: SQLiteSessionRepository?
    private var pendingSaveTimer: Timer?

    var runtime: GhosttyRuntime?
    var attentionCenter: AttentionCenter?
    var agentEventServer: AgentEventServer?
    var paneInputScheduler: PaneInputScheduler?
    var settingsModel: SettingsModel?
    var isRemoteAccessConnected = false

    private let updateAgentSleepPrevention: () -> Void
    private let setAgentSleepPreventionMode: (AgentSleepPreventionMode) -> Void
    private let presentActionError: (Error) -> Void
    private let broadcastSnapshot: () -> Void
    private let closeSettingsIfNeeded: (Int) -> Void

    init(
        updateAgentSleepPrevention: @escaping () -> Void,
        setAgentSleepPreventionMode: @escaping (AgentSleepPreventionMode) -> Void,
        presentActionError: @escaping (Error) -> Void,
        broadcastSnapshot: @escaping () -> Void,
        closeSettingsIfNeeded: @escaping (Int) -> Void
    ) {
        self.updateAgentSleepPrevention = updateAgentSleepPrevention
        self.setAgentSleepPreventionMode = setAgentSleepPreventionMode
        self.presentActionError = presentActionError
        self.broadcastSnapshot = broadcastSnapshot
        self.closeSettingsIfNeeded = closeSettingsIfNeeded
    }

    var activeController: TerminalWindowController? {
        guard let keyWindow = NSApplication.shared.keyWindow else {
            return controllers.first
        }
        return controllers.first { $0.window === keyWindow }
    }

    func focus(surface surfaceID: TerminalSurfaceID) {
        for controller in controllers where controller.focus(surface: surfaceID) {
            return
        }
    }

    func focus(
        pane paneID: TerminalSurfaceID,
        in windowID: WindowID
    ) {
        guard let controller = controllers.first(where: {
            $0.session.id == windowID
        }) else { return }
        _ = controller.focus(pane: paneID)
    }

    func createWindow(workingDirectory: URL) throws {
        let fallbackFrame = WindowFrame(
            x: 160,
            y: 140,
            width: 1100,
            height: 720
        )
        let preferences = settingsModel?.application
            ?? ApplicationPreferences()
        let rememberedFrame = activeController?.session.frame
            ?? rememberedWindowFrame
        let plan = WindowStartupPlan.make(
            behavior: preferences.windowStartupBehavior,
            rememberedFrame: rememberedFrame,
            fallbackFrame: fallbackFrame,
            maximumFrame: maximumWindowFrame(
                for: rememberedFrame ?? fallbackFrame
            )
        )
        let surface = TerminalSurfaceState(
            workingDirectory: workingDirectory
        )
        let tab = TabSession(initialSurface: surface)
        let session = WindowSession(
            frame: plan.frame,
            tabs: [tab],
            selectedTabID: tab.id
        )
        try createWindow(session: session)
    }

    func createWindow(
        session: WindowSession,
        adopting transfer: TerminalTabTransfer? = nil
    ) throws {
        guard let runtime,
              let attentionCenter,
              let agentEventServer,
              let paneInputScheduler,
              let settingsModel
        else { return }

        let windowID = session.id
        let controller = try TerminalWindowController(
            session: session,
            runtime: runtime,
            attentionCenter: attentionCenter,
            agentEventServer: agentEventServer,
            paneInputScheduler: paneInputScheduler,
            applicationPreferences: settingsModel.application,
            tabDragCoordinator: tabDragCoordinator,
            closedPaneHistory: closedPaneHistory,
            adopting: transfer,
            onSessionChanged: { [weak self] session in
                self?.rememberedWindowFrame = session.frame
                self?.saveSessions()
            },
            onWindowClosed: { [weak self] id in
                self?.removeWindow(id: id)
            },
            onNewWindowRequested: { [weak self] directory in
                do {
                    try self?.createWindow(workingDirectory: directory)
                } catch {
                    self?.presentActionError(error)
                }
            },
            onFocusSurfaceRequested: { [weak self] surfaceID in
                self?.focus(surface: surfaceID)
            },
            onAgentActivityChanged: { [weak self] in
                self?.updateAgentSleepPrevention()
            },
            onSleepPreventionModeSelected: { [weak self] mode in
                self?.setAgentSleepPreventionMode(mode)
            },
            onTabDropRequested: { [weak self] insertionIndex in
                self?.transferDraggedTab(
                    to: windowID,
                    at: insertionIndex
                )
            },
            onTabDragSessionEnded: { [weak self] tabID, screenPoint in
                self?.finishTabDragSession(
                    tabID: tabID,
                    endedAt: screenPoint
                )
            }
        )
        controllers.append(controller)
        controller.setRemoteAccessConnected(isRemoteAccessConnected)
        updateAgentSleepPrevention()
        rememberedWindowFrame = session.frame
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        saveSessions()
    }

    func transferDraggedTab(
        to targetWindowID: WindowID,
        at insertionIndex: Int
    ) {
        guard let payload = tabDragCoordinator.payload,
              !tabDragCoordinator.isConsumed,
              payload.windowID != targetWindowID,
              let source = controllers.first(where: {
                  $0.session.id == payload.windowID
              }),
              let target = controllers.first(where: {
                  $0.session.id == targetWindowID
              }),
              let transfer = source.beginTabTransfer(payload.tabID)
        else { return }
        tabDragCoordinator.consume()
        target.adopt(transfer, at: insertionIndex)
    }

    func finishTabDragSession(
        tabID: TabID,
        endedAt screenPoint: NSPoint
    ) {
        defer { tabDragCoordinator.end() }
        guard let payload = tabDragCoordinator.payload,
              payload.tabID == tabID,
              let source = controllers.first(where: {
                  $0.session.id == payload.windowID
              }),
              TabTearOffPlan.shouldTearOff(
                  isConsumed: tabDragCoordinator.isConsumed,
                  sourceTabCount: source.session.tabs.count
              )
        else { return }

        let frame = TabTearOffPlan.windowFrame(
            endedAt: screenPoint,
            size: CGSize(
                width: source.session.frame.width,
                height: source.session.frame.height
            )
        )
        guard let transfer = source.beginTabTransfer(tabID) else { return }
        tabDragCoordinator.consume()
        do {
            try createWindow(
                session: WindowSession(
                    frame: WindowFrame(
                        x: frame.origin.x,
                        y: frame.origin.y,
                        width: frame.width,
                        height: frame.height
                    ),
                    tabs: [transfer.tab],
                    selectedTabID: transfer.tab.id
                ),
                adopting: transfer
            )
        } catch {
            presentActionError(error)
        }
    }

    func removeWindow(id: WindowID) {
        controllers.removeAll { $0.session.id == id }
        closeSettingsIfNeeded(controllers.count)
        updateAgentSleepPrevention()
        saveSessions()
    }

    func loadRestorableState(
        from repository: SQLiteSessionRepository
    ) -> RestorableSessionState {
        sessionRepository = repository
        do {
            guard let snapshot = try repository.load() else {
                return RestorableSessionState()
            }

            var windowIDs = Set<WindowID>()
            let sessions = snapshot.windows.filter { session in
                windowIDs.insert(session.id).inserted
                    && session.isStructurallyRestorable
            }
            return RestorableSessionState(
                sessions: sessions,
                lastWindowFrame: snapshot.lastWindowFrame
            )
        } catch {
            sessionRepository = nil
            Self.reportPersistenceError(error, operation: "restore")
            return RestorableSessionState()
        }
    }

    /// Saves the window/tab structure. Two things keep this off the
    /// critical path of a tab switch, which triggers it: scrollback is not
    /// re-read (that costs tens of milliseconds per pane —
    /// `captureTerminalHistories()` owns it), and the write itself is
    /// coalesced, so holding a tab-switch key down writes once.
    func saveSessions() {
        guard terminationState.shouldSaveAfterWindowRemoval else { return }
        scheduleSave()
    }

    /// Saves with every pane's current scrollback. Called when the app goes
    /// inactive, on the periodic timer, and at termination — the points
    /// where a restore (or a crash) would otherwise lose terminal content.
    func captureTerminalHistories() {
        guard terminationState.shouldSaveAfterWindowRemoval else { return }
        persistSessions(history: .fresh)
    }

    func captureTerminationSnapshotIfNeeded() {
        guard terminationState.beginTermination() else { return }
        persistSessions(history: .fresh)
    }

    private func scheduleSave() {
        guard pendingSaveTimer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingSaveTimer = nil
                self.persistSessions(history: .reusingLastCapture)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingSaveTimer = timer
    }

    private func persistSessions(history: TerminalHistoryCapture) {
        pendingSaveTimer?.invalidate()
        pendingSaveTimer = nil
        guard !isRestoringSessions, let sessionRepository else { return }

        do {
            try sessionRepository.save(
                SessionSnapshot(
                    windows: controllers.map {
                        $0.sessionSnapshotForRestoration(history: history)
                    },
                    lastWindowFrame: rememberedWindowFrame
                )
            )
        } catch {
            Self.reportPersistenceError(error, operation: "save")
        }
        broadcastSnapshot()
    }

    func maximumWindowFrame(for reference: WindowFrame) -> WindowFrame {
        let referenceRect = NSRect(
            x: reference.x,
            y: reference.y,
            width: reference.width,
            height: reference.height
        )
        let overlappingScreen = NSScreen.screens.max { left, right in
            intersectionArea(left.frame, referenceRect)
                < intersectionArea(right.frame, referenceRect)
        }
        let targetScreen: NSScreen?
        if let overlappingScreen,
           intersectionArea(overlappingScreen.frame, referenceRect) > 0 {
            targetScreen = overlappingScreen
        } else {
            targetScreen = NSScreen.main ?? NSScreen.screens.first
        }
        guard let frame = targetScreen?.visibleFrame else { return reference }
        return WindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    private func intersectionArea(_ left: NSRect, _ right: NSRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    static func reportPersistenceError(
        _ error: Error,
        operation: String
    ) {
        let message = "\(ApplicationIdentity.displayName) session "
            + "\(operation) failed: \(error)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}

struct RestorableSessionState {
    var sessions: [WindowSession] = []
    var lastWindowFrame: WindowFrame?
}

extension WindowSession {
    var isStructurallyRestorable: Bool {
        guard frame.width > 0,
              frame.height > 0,
              frame.x.isFinite,
              frame.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              !tabs.isEmpty,
              tabs.contains(where: { $0.id == selectedTabID })
        else { return false }

        let tabIDs = tabs.map(\.id)
        guard Set(tabIDs).count == tabIDs.count else { return false }

        let paneIDs = tabs.flatMap(\.paneIDs)
        guard Set(paneIDs).count == paneIDs.count else { return false }

        return tabs.allSatisfy {
            $0.paneIDs.contains($0.focusedSurfaceID)
        }
    }
}
