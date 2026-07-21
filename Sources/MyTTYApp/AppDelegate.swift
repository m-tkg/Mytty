import AppKit
import GhosttyAdapter
import MyTTYCore

enum ApplicationWindowLifecycle {
    static func shouldCloseSettings(
        remainingTerminalWindowCount: Int
    ) -> Bool {
        remainingTerminalWindowCount == 0
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var runtime: GhosttyRuntime?
    private var attentionCenter: AttentionCenter?
    private var agentEventServer: AgentEventServer?
    private var controlCoordinator: ControlCoordinator?
    private var remoteAccessCoordinator: RemoteAccessCoordinator?
    private var attentionNotifier: AttentionNotifier?
    private var remotePushNotifier: RemoteAttentionPushNotifier?
    private var agentIntegrationSettingsModel: AgentIntegrationSettingsModel?
    private var settingsModel: SettingsModel?
    private var settingsWindowController: SettingsWindowController?
    private var terminalHistoryCaptureTimer: Timer?
    private var aboutWindowController: AboutWindowController?
    private var paneListWindowController: PaneListWindowController?
    private lazy var windowSessionCoordinator = WindowSessionCoordinator(
        updateAgentSleepPrevention: { [weak self] in
            self?.updateAgentSleepPrevention()
        },
        setAgentSleepPreventionMode: { [weak self] mode in
            self?.setAgentSleepPreventionMode(mode)
        },
        presentActionError: { [weak self] error in
            self?.presentActionError(error)
        },
        broadcastSnapshot: { [weak self] in
            self?.remoteAccessCoordinator?.server.broadcastSnapshot()
        },
        closeSettingsIfNeeded: { [weak self] remainingCount in
            if ApplicationWindowLifecycle.shouldCloseSettings(
                remainingTerminalWindowCount: remainingCount
            ) {
                self?.settingsWindowController?.close()
            }
        }
    )
    private lazy var cursorApprovalCoordinator = CursorApprovalCoordinator(
        deliver: { [weak self] event in
            self?.deliverSyntheticAgentEvent(event)
        }
    )
    private let agentSleepPrevention = AgentSleepPreventionController()
    private lazy var clamshellSleepBlocker = ClamshellSleepBlocker(
        flagURL: ApplicationPaths(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            temporaryDirectory: URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            ),
            profile: ApplicationIdentity.pathProfile
        ).configurationDirectory
            .appendingPathComponent("clamshell.armed")
    )
    private var terminalAppearance: TerminalAppearance = .system
    private var localizer = MyTTYLocalizer(language: .systemDefault)
    private var commandPaletteController: CommandPaletteController?
    private var appearanceObservation: NSKeyValueObservation?
    private var shortcutRouter: ApplicationShortcutRouter?
    private var oneLinerPanel: OneLinerPanelController?
    private lazy var applicationUpdateCoordinator = ApplicationUpdateCoordinator(
        localizerProvider: { [weak self] in
            self?.localizer ?? MyTTYLocalizer(language: .systemDefault)
        },
        presentActionError: { [weak self] error in
            self?.presentActionError(error)
        }
    )
    private var applicationUpdateModel: ApplicationUpdateModel {
        applicationUpdateCoordinator.model
    }
    private lazy var defaultTerminalModel = DefaultTerminalModel(
        applicationURL: Bundle.main.bundleURL,
        registrar: WorkspaceDefaultTerminalRegistrar()
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            clamshellSleepBlocker.onChange = { [weak self] in
                self?.updateAgentSleepPrevention()
            }
            clamshellSleepBlocker.confirmApprovalPrompt = { [weak self] in
                self?.confirmClamshellApprovalPrompt() ?? false
            }
            clamshellSleepBlocker.prepare()
            try launchApplication()
            startTerminalHistoryCapture()
            if ApplicationIdentity.supportsSelfUpdate {
                applicationUpdateCoordinator.checkForUpdates(trigger: .launch)
            }
        } catch {
            presentLaunchError(error)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        runtime?.setFocused(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        runtime?.setFocused(false)
        // Leaving the app is the natural moment to bank the scrollback the
        // routine saves skip, alongside the periodic capture below.
        windowSessionCoordinator.captureTerminalHistories()
    }

    /// Keeps the stored scrollback recent enough that a crash (which never
    /// reaches `applicationWillTerminate`) still restores useful terminal
    /// content, without making every tab switch pay to read it.
    private func startTerminalHistoryCapture() {
        let timer = Timer(
            timeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowSessionCoordinator.captureTerminalHistories()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        terminalHistoryCaptureTimer = timer
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        windowSessionCoordinator.captureTerminationSnapshotIfNeeded()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        clamshellSleepBlocker.setDesired(keepAwake: false)
        windowSessionCoordinator.captureTerminationSnapshotIfNeeded()
        agentEventServer?.stop()
        controlCoordinator?.stop()
        agentSleepPrevention.stop()
        appearanceObservation?.invalidate()
        shortcutRouter = nil
    }

    func makeMainMenu(
        keyBindings: [MyTTYCommand: MyTTYKeyBinding]
            = MyTTYCommand.defaultKeyBindings,
        localizer: MyTTYLocalizer = MyTTYLocalizer(language: .english)
    ) -> NSMenu {
        MainMenuBuilder.makeMainMenu(
            keyBindings: keyBindings,
            localizer: localizer,
            target: self
        )
    }

    @objc func newWindow(_ sender: Any?) {
        do {
            try windowSessionCoordinator.createWindow(
                workingDirectory: activeWorkingDirectory
            )
        } catch {
            presentActionError(error)
        }
    }

    @objc func newTab(_ sender: Any?) {
        windowSessionCoordinator.activeController?.newTab()
    }

    @objc func openHTML(_ sender: Any?) {
        windowSessionCoordinator.activeController?.openHTMLFile()
    }

    @objc func closeTab(_ sender: Any?) {
        windowSessionCoordinator.activeController?.closeSelectedTab()
    }

    @objc func reopenClosed(_ sender: Any?) {
        windowSessionCoordinator.activeController?.reopenMostRecentClosed()
    }

    @objc func reopenClosedEntry(_ sender: NSMenuItem) {
        guard let entryID = sender.representedObject as? UUID else { return }
        windowSessionCoordinator.activeController?.reopen(entryID: entryID)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = windowSessionCoordinator.closedPaneHistory.entries
        guard !entries.isEmpty else {
            let placeholder = menu.addItem(
                withTitle: localizer[.noRecentlyClosedItems],
                action: nil,
                keyEquivalent: ""
            )
            placeholder.isEnabled = false
            return
        }
        for entry in entries {
            let item = menu.addItem(
                withTitle: closedPaneHistoryTitle(for: entry),
                action: #selector(reopenClosedEntry(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.id
        }
    }

    private func closedPaneHistoryTitle(
        for entry: ClosedPaneHistoryEntry
    ) -> String {
        switch entry.record {
        case let .terminal(state):
            let url = state.workingDirectory
            return url.path == "/" ? "/" : url.lastPathComponent
        case let .browser(state):
            if state.url.isFileURL {
                return state.url.lastPathComponent.isEmpty
                    ? localizer[.browser]
                    : state.url.lastPathComponent
            }
            return state.url.host(percentEncoded: false)
                ?? (state.url.absoluteString.isEmpty
                    ? localizer[.browser]
                    : state.url.absoluteString)
        case let .tab(tab):
            let baseName = tab.pinnedTitle
                ?? TerminalTabTitle.defaultTitle(for: tab, localizer: localizer)
            return tab.paneIDs.count > 1
                ? "\(baseName) (\(localizer.paneCount(tab.paneIDs.count)))"
                : baseName
        }
    }

    @objc func renameTab(_ sender: Any?) {
        windowSessionCoordinator.activeController?.renameSelectedTab()
    }

    @objc func splitRight(_ sender: Any?) {
        windowSessionCoordinator.activeController?.splitFocusedPane(.right)
    }

    @objc func splitLeft(_ sender: Any?) {
        windowSessionCoordinator.activeController?.splitFocusedPane(.left)
    }

    @objc func splitUp(_ sender: Any?) {
        windowSessionCoordinator.activeController?.splitFocusedPane(.up)
    }

    @objc func splitDown(_ sender: Any?) {
        windowSessionCoordinator.activeController?.splitFocusedPane(.down)
    }

    @objc func focusPaneLeft(_ sender: Any?) {
        windowSessionCoordinator.activeController?.focusPane(.left)
    }

    @objc func focusPaneRight(_ sender: Any?) {
        windowSessionCoordinator.activeController?.focusPane(.right)
    }

    @objc func focusPaneUp(_ sender: Any?) {
        windowSessionCoordinator.activeController?.focusPane(.up)
    }

    @objc func focusPaneDown(_ sender: Any?) {
        windowSessionCoordinator.activeController?.focusPane(.down)
    }

    @objc func equalizePanes(_ sender: Any?) {
        windowSessionCoordinator.activeController?.equalizePanes()
    }

    @objc func togglePaneZoom(_ sender: Any?) {
        windowSessionCoordinator.activeController?.togglePaneZoom()
    }

    @objc func swapPanes(_ sender: Any?) {
        windowSessionCoordinator.activeController?.toggleSwapPanesMode()
    }

    @objc func findInPane(_ sender: Any?) {
        windowSessionCoordinator.activeController?.findInFocusedPane()
    }

    @objc func explainPane(_ sender: Any?) {
        windowSessionCoordinator.activeController?.explainFocusedPane()
    }

    @objc func summarizeLastCommand(_ sender: Any?) {
        windowSessionCoordinator.activeController?
            .summarizeLastCommandResult()
    }

    @objc func composeOneLiner(_ sender: Any?) {
        guard #available(macOS 26, *) else { return }
        let panel = oneLinerPanel ?? OneLinerPanelController(
            localizer: localizer
        ) { [weak self] request in
            let language = self?.settingsModel?.application.language
                ?? .systemDefault
            return await OneLinerComposer.compose(
                request: request,
                language: language.resolved()
            )
        }
        oneLinerPanel = panel
        panel.show()
    }

    @objc func showPaneList(_ sender: Any?) {
        let sourceController = windowSessionCoordinator.activeController
        let visibleScreenFrame = NSApplication.shared.keyWindow?
            .screen?.visibleFrame
            ?? sourceController?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        let selectedPaneID = sourceController?
            .session.selectedTab?.focusedSurfaceID
        let items = PaneListPresentation.items(
            snapshots: windowSessionCoordinator.controllers.map {
                $0.paneListSnapshot()
            },
            terminalTitle: localizer[.terminal],
            browserTitle: localizer[.browser],
            localizer: localizer
        )
        if paneListWindowController == nil {
            paneListWindowController = PaneListWindowController(
                onFocus: { [weak self] item in
                    self?.windowSessionCoordinator.focus(
                        pane: item.paneID,
                        in: item.windowID
                    )
                }
            )
        }
        paneListWindowController?.present(
            items: items,
            selectedPaneID: selectedPaneID,
            visibleScreenFrame: visibleScreenFrame,
            localizer: localizer
        )
    }

    @objc func closePane(_ sender: Any?) {
        windowSessionCoordinator.activeController?.closeFocusedPane()
    }

    @objc func toggleAttention(_ sender: Any?) {
        windowSessionCoordinator.activeController?.toggleAttention()
    }

    @objc func toggleTabPanels(_ sender: Any?) {
        windowSessionCoordinator.activeController?.toggleTabPanels()
    }

    @objc func toggleRecording(_ sender: Any?) {
        windowSessionCoordinator.activeController?.toggleRecording()
    }

    @objc func showCommandPalette(_ sender: Any?) {
        // Rebuilt per show so the entries and chrome always reflect the
        // current menu (language, macOS-26-gated items, key bindings).
        let controller = CommandPaletteController(localizer: localizer)
        commandPaletteController = controller
        controller.show(
            excluding: #selector(AppDelegate.showCommandPalette(_:))
        )
    }

    @objc func showSettings(_ sender: Any?) {
        guard let settingsModel,
              let agentIntegrationSettingsModel,
              let remoteAccessCoordinator
        else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsModel: settingsModel,
                integrationsModel: agentIntegrationSettingsModel,
                updateModel: applicationUpdateModel,
                defaultTerminalModel: defaultTerminalModel,
                remoteAccessModel: remoteAccessCoordinator.settingsModel
            )
        }
        settingsWindowController?.present()
    }

    @objc func showAbout(_ sender: Any?) {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController(
                model: applicationUpdateModel,
                localizer: localizer
            )
        }
        aboutWindowController?.present()
    }

    private var activeWorkingDirectory: URL {
        windowSessionCoordinator.activeController?.currentWorkingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func launchApplication() throws {
        let fileManager = FileManager.default
        let paths = ApplicationPaths(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            temporaryDirectory: URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            ),
            profile: ApplicationIdentity.pathProfile
        )
        let sharedIntegrationPaths = ApplicationPaths(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            temporaryDirectory: URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            ),
            profile: .release
        )
        try ApplicationFileSystem().prepare(paths)
        try TerminalPreferencesStore().prepareForLaunch(
            at: paths.terminalConfiguration
        )
        let agentIntegrationSettingsModel = AgentIntegrationSettingsModel(
            installer: AgentIntegrationInstaller(
                homeDirectory: fileManager.homeDirectoryForCurrentUser,
                applicationSupportDirectory:
                    sharedIntegrationPaths.applicationSupportDirectory,
                sourceHookExecutable: sourceHookExecutable()
            ),
            preferenceStore: ApplicationPreferencesPaneTeamPointerStore(
                store: ApplicationPreferencesStore(),
                configurationURL: paths.appConfiguration
            )
        )
        // A single canonical copy shared by dev and release builds, same
        // reasoning as mytty-agent-hook: mytty-ctl only reads
        // MYTTY_CONTROL_SOCKET per invocation, so which Mytty variant
        // launched the pane doesn't matter for where the binary lives —
        // only external hook configs need a stable, shared path, and this
        // is exposed to panes the same way (an env var), not a hook config,
        // but keeping one copy avoids two binaries to keep in sync.
        let installedControlExecutable = installControlExecutable(
            applicationSupportDirectory:
                sharedIntegrationPaths.applicationSupportDirectory
        )
        agentIntegrationSettingsModel.repairInstalledIntegrations()
        self.agentIntegrationSettingsModel = agentIntegrationSettingsModel
        remoteAccessCoordinator = RemoteAccessCoordinator(
            deviceStoreURL: paths.remoteDevices,
            deviceDisplayName: Host.current().localizedName ?? "Mytty",
            windowSessionCoordinator: windowSessionCoordinator,
            localizerProvider: { [weak self] in
                self?.localizer ?? MyTTYLocalizer(language: .systemDefault)
            }
        )
        try GhosttyLibrary.initializeCurrentProcess(
            resourcesDirectory: GhosttyResourceLocator.current()
        )

        let configuration = try GhosttyConfiguration(
            file: paths.terminalConfiguration
        )
        let runtime = try GhosttyRuntime(configuration: configuration)
        runtime.setFocused(NSApplication.shared.isActive)
        self.runtime = runtime
        windowSessionCoordinator.runtime = runtime
        settingsModel = try SettingsModel(
            paths: paths,
            onTerminalConfigurationChanged: { [weak self] preferences in
                guard let self, let runtime = self.runtime else { return }
                let updated = try GhosttyConfiguration(
                    file: paths.terminalConfiguration
                )
                guard updated.diagnostics.isEmpty else {
                    throw TerminalSettingsError.invalidConfiguration(
                        updated.diagnostics
                    )
                }
                runtime.updateConfiguration(updated)
                self.applyTerminalPresentation(preferences)
            },
            onApplicationPreferencesChanged: { [weak self] preferences in
                self?.applyApplicationPreferences(preferences)
            }
        )
        if let preferences = settingsModel?.application {
            applyApplicationPreferences(preferences)
        }
        if let preferences = settingsModel?.terminal {
            applyTerminalPresentation(preferences)
        }
        observeEffectiveAppearance()
        scheduleStartupFontRefresh(
            terminalConfiguration: paths.terminalConfiguration
        )
        windowSessionCoordinator.settingsModel = settingsModel
        let repository = SQLiteSessionRepository(databaseURL: paths.database)
        let paneInputScheduler = PaneInputScheduler(
            repository: SQLitePaneInputScheduleRepository(
                databaseURL: paths.database
            ),
            onFire: { [weak self] schedule in
                self?.deliverScheduledInput(schedule)
            },
            onError: { error in
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "scheduled input"
                )
            }
        )
        windowSessionCoordinator.paneInputScheduler = paneInputScheduler
        let attentionCenter = AttentionCenter(
            repository: SQLiteAgentEventRepository(
                databaseURL: paths.database
            )
        )
        do {
            try attentionCenter.reload()
            // Completions from before this launch were already lived
            // through — start the inbox without them.
            try attentionCenter.acknowledgeCompletions(before: Date())
        } catch {
            WindowSessionCoordinator.reportPersistenceError(
                error,
                operation: "restore attention"
            )
        }
        self.attentionCenter = attentionCenter
        windowSessionCoordinator.attentionCenter = attentionCenter
        if Bundle.main.bundleIdentifier != nil {
            attentionNotifier = AttentionNotifier(
                localizer: localizer,
                onFocus: { [weak self] surfaceID in
                    self?.windowSessionCoordinator.focus(surface: surfaceID)
                },
                onError: { error in
                    WindowSessionCoordinator.reportPersistenceError(
                        error,
                        operation: "notification"
                    )
                }
            )
        }
        remotePushNotifier = RemoteAttentionPushNotifier(
            deviceStore: RemotePairedDeviceStore(fileURL: paths.remoteDevices),
            localizer: localizer,
            isEnabled: { [weak self] in
                self?.settingsModel?.application
                    .remotePushNotificationsEnabled ?? false
            },
            onError: { error in
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "push notification"
                )
            }
        )
        let eventServer = AgentEventServer(
            socketURL: paths.controlSocket,
            aiControlSocketURL: paths.aiControlSocket,
            aiControlExecutableURL: installedControlExecutable,
            onEvent: { [weak self] event in
                guard let self else { return false }
                return try self.receiveAgentEvent(event)
            },
            onError: { error in
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "agent event"
                )
            }
        )
        try eventServer.start()
        agentEventServer = eventServer
        windowSessionCoordinator.agentEventServer = eventServer

        let controlCoordinator = ControlCoordinator(
            socketURL: paths.aiControlSocket,
            windowSessionCoordinator: windowSessionCoordinator,
            attentionCenter: attentionCenter,
            localizerProvider: { [weak self] in
                self?.localizer ?? MyTTYLocalizer(language: .systemDefault)
            },
            agentIntegrationStatus: { [weak self] provider in
                self?.agentIntegrationSettingsModel?
                    .state(for: provider).status ?? .notInstalled
            },
            onError: { error in
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "ai control"
                )
            }
        )
        try controlCoordinator.start()
        self.controlCoordinator = controlCoordinator

        let savedState = windowSessionCoordinator.loadRestorableState(
            from: repository
        )
        let savedSessions = savedState.sessions
        windowSessionCoordinator.rememberedWindowFrame = savedState.lastWindowFrame
            ?? savedSessions.first?.frame
        let restoredSessions = ApplicationLaunchPolicy.sessionsToRestore(
            savedSessions,
            behavior: settingsModel?.application.launchBehavior
                ?? .restoreLastSession
        )
        windowSessionCoordinator.isRestoringSessions = true
        for savedSession in restoredSessions {
            do {
                let preferences = settingsModel?.application
                    ?? ApplicationPreferences()
                let plan = WindowStartupPlan.make(
                    behavior: preferences.windowStartupBehavior,
                    rememberedFrame: savedSession.frame,
                    fallbackFrame: savedSession.frame,
                    maximumFrame: windowSessionCoordinator.maximumWindowFrame(
                        for: savedSession.frame
                    )
                )
                var session = savedSession
                session.frame = plan.frame
                try windowSessionCoordinator.createWindow(session: session)
            } catch {
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "restore window"
                )
            }
        }
        windowSessionCoordinator.isRestoringSessions = false

        if windowSessionCoordinator.controllers.isEmpty {
            let processDirectory = URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )
            try windowSessionCoordinator.createWindow(
                workingDirectory: ApplicationLaunchPolicy
                    .initialWorkingDirectory(
                        homeDirectory: fileManager.homeDirectoryForCurrentUser,
                        processDirectory: processDirectory
                    )
            )
        }
        try paneInputScheduler.reload(
            validSurfaceIDs: PaneInputScheduleScope.liveSurfaceIDs(
                in: windowSessionCoordinator.controllers.map(\.session)
            )
        )
        windowSessionCoordinator.saveSessions()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func sourceHookExecutable() -> URL {
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            return Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers", isDirectory: true)
                .appendingPathComponent(
                    "mytty-agent-hook",
                    isDirectory: false
                )
        }
        let appExecutable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return appExecutable.deletingLastPathComponent()
            .appendingPathComponent("mytty-agent-hook", isDirectory: false)
    }

    private func sourceControlExecutable() -> URL {
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            return Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers", isDirectory: true)
                .appendingPathComponent("mytty-ctl", isDirectory: false)
        }
        let appExecutable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return appExecutable.deletingLastPathComponent()
            .appendingPathComponent("mytty-ctl", isDirectory: false)
    }

    /// Copies the `mytty-ctl` binary next to `mytty-agent-hook`'s installed
    /// copy so every pane's `MYTTY_CTL_BIN` env var (see
    /// `AgentEventServer.environment(for:)`) resolves to something that
    /// actually runs, without requiring `mytty-ctl` on `PATH`. Best-effort:
    /// a failure here shouldn't block launch, since AI pane control is an
    /// additive capability, not a requirement to use Mytty.
    @discardableResult
    private func installControlExecutable(
        applicationSupportDirectory: URL
    ) -> URL {
        let source = sourceControlExecutable()
        let destination = applicationSupportDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("mytty-ctl", isDirectory: false)
        guard source.standardizedFileURL != destination.standardizedFileURL
        else { return destination }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
        } catch {
            WindowSessionCoordinator.reportPersistenceError(
                error,
                operation: "install mytty-ctl"
            )
        }
        return destination
    }

    private func applyApplicationPreferences(
        _ preferences: ApplicationPreferences
    ) {
        localizer = MyTTYLocalizer(language: preferences.language)
        NSApplication.shared.mainMenu = makeMainMenu(
            keyBindings: preferences.keyBindings,
            localizer: localizer
        )
        if let shortcutRouter {
            shortcutRouter.update(bindings: preferences.keyBindings)
        } else {
            shortcutRouter = ApplicationShortcutRouter(
                bindings: preferences.keyBindings,
                onKeyPressed: { [weak self] event in
                    self?.windowSessionCoordinator.activeController?
                        .showPressedKey(event)
                }
            )
        }
        windowSessionCoordinator.controllers.forEach {
            $0.updateApplicationPreferences(preferences)
        }
        updateAgentSleepPrevention()
        settingsWindowController?.updateLocalization(localizer)
        aboutWindowController?.updateLocalization(localizer)
        paneListWindowController?.updateLocalization(localizer)
        attentionNotifier?.updateLocalization(localizer)
        remotePushNotifier?.updateLocalization(localizer)
        remoteAccessCoordinator?.updateRemoteAccessServer(
            enabled: preferences.remoteAccessEnabled
        )
    }

    private func applyTerminalPresentation(
        _ preferences: TerminalPreferences
    ) {
        terminalAppearance = preferences.appearance
        NSApplication.shared.appearance = preferences.appearance.appKitAppearance
        syncGhosttyColorScheme()
        windowSessionCoordinator.controllers.forEach {
            $0.refreshTerminalPresentation()
        }
    }

    /// Shortly after launch, CoreText can resolve a different (wrong)
    /// CJK fallback for the configured font than it does once the process
    /// has settled — Japanese glyphs render in the wrong face until the
    /// user re-applies the font in Settings. Mirror that manual fix
    /// automatically: re-apply the identical terminal configuration a few
    /// seconds after launch (twice, for slower machines), which rebuilds
    /// the font grid against the settled fallback. A no-op when the
    /// initial resolution was already correct.
    private func scheduleStartupFontRefresh(
        terminalConfiguration: URL
    ) {
        for delay: TimeInterval in [3, 8, 20, 45] {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay
            ) { [weak self] in
                self?.reapplyTerminalConfiguration(terminalConfiguration)
            }
        }

        // Right after a cold boot, fontd may not have indexed user fonts
        // yet, so the configured family resolves to a substitute no matter
        // how often the grid is rebuilt. Watch for the family to actually
        // register and re-apply the moment it does.
        let family = settingsModel?.terminal.fontFamily ?? ""
        guard !family.isEmpty,
              !Self.fontFamilyIsRegistered(family)
        else { return }
        Task { @MainActor [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                guard self != nil else { return }
                if Self.fontFamilyIsRegistered(family) {
                    self?.reapplyTerminalConfiguration(
                        terminalConfiguration
                    )
                    return
                }
            }
        }
    }

    private func reapplyTerminalConfiguration(_ file: URL) {
        guard let runtime,
              let configuration = try? GhosttyConfiguration(file: file),
              configuration.diagnostics.isEmpty
        else { return }
        runtime.updateConfiguration(configuration)
    }

    private static func fontFamilyIsRegistered(_ family: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
        ] as CFDictionary)
        let mandatoryKeys = Set([kCTFontFamilyNameAttribute as String])
        guard let matched = CTFontDescriptorCreateMatchingFontDescriptor(
            descriptor,
            mandatoryKeys as CFSet
        ) else { return false }
        let name = CTFontDescriptorCopyAttribute(
            matched,
            kCTFontFamilyNameAttribute
        ) as? String
        return name?.caseInsensitiveCompare(family) == .orderedSame
    }

    private func observeEffectiveAppearance() {
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] application, _ in
            MainActor.assumeIsolated {
                self?.syncGhosttyColorScheme(
                    effectiveAppearance: application.effectiveAppearance
                )
            }
        }
    }

    private func syncGhosttyColorScheme(
        effectiveAppearance: NSAppearance
            = NSApplication.shared.effectiveAppearance
    ) {
        runtime?.setColorScheme(
            terminalAppearance.ghosttyColorScheme(
                effectiveAppearance: effectiveAppearance
            )
        )
    }

    private func deliverScheduledInput(_ schedule: PaneInputSchedule) {
        for controller in windowSessionCoordinator.controllers
            where controller.deliverScheduledInput(schedule) {
            return
        }
    }

    private func updateAgentSleepPrevention() {
        let mode = settingsModel?.application.agentSleepPreventionMode
            ?? .allowSleep
        let controllers = windowSessionCoordinator.controllers
        let windowAgentIsActive: [Bool] = switch mode {
        case .allowSleep:
            []
        case .preventWhileProcessing:
            controllers.map(\.hasProcessingAgent)
        case .preventWhileLaunched:
            controllers.map(\.hasLaunchedAgent)
        }
        agentSleepPrevention.update(
            mode: mode,
            windowAgentIsActive: windowAgentIsActive
        )
        // The lid-closed override follows the sleep assertion: whenever
        // sleep prevention is in effect, clamshell sleep is disabled too
        // (via the privileged helper, without any password prompt).
        clamshellSleepBlocker.setDesired(
            keepAwake: agentSleepPrevention.status.isActive
        )
        var status = agentSleepPrevention.status
        status.keepsLidClosedAwake = clamshellSleepBlocker.isArmed
        // Surface the pending approval (and any registration failure)
        // whenever a prevention mode is selected, even while no agent is
        // active yet — otherwise the helper looks silently broken.
        status.needsClamshellApproval = mode != .allowSleep
            && clamshellSleepBlocker.needsBackgroundItemApproval
        status.clamshellHelperIssue = mode != .allowSleep
            ? clamshellSleepBlocker.registrationErrorDescription
            : nil
        controllers.forEach {
            $0.updateAgentSleepStatus(status)
        }
    }

    /// Explains the one-time background-item approval before System
    /// Settings (and its Touch ID / password sheet) appears, so the
    /// request never comes out of nowhere.
    private func confirmClamshellApprovalPrompt() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localizer[.sleepClamshellApprovalPromptTitle]
        alert.informativeText =
            localizer[.sleepClamshellApprovalPromptMessage]
        alert.addButton(withTitle: localizer[.openSystemSettings])
        alert.addButton(withTitle: localizer[.notNow])
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func setAgentSleepPreventionMode(
        _ mode: AgentSleepPreventionMode
    ) {
        // A menu selection of a prevention mode is an explicit gesture:
        // if the lid-closed helper still needs its one-time approval,
        // explain and offer System Settings right now instead of at some
        // arbitrary later moment.
        if mode != .allowSleep {
            clamshellSleepBlocker.noteUserIntent()
        }
        settingsModel?.updateApplication {
            $0.agentSleepPreventionMode = mode
        }
    }

    private func receiveAgentEvent(_ event: AgentEvent) throws -> Bool {
        guard let attentionCenter else { return false }
        cursorApprovalCoordinator.observe(event)
        let inserted = try attentionCenter.append(event)
        if inserted {
            updateAgentSleepPrevention()
        }
        guard inserted,
              let item = attentionCenter.items.first(where: {
                  $0.id == event.id && $0.isActionable
              })
        else { return inserted }

        // The phone is gated on the Mac being unattended rather than on
        // pane visibility: the case this exists for is walking away from a
        // running agent, where the pane is still focused on screen and the
        // Mac deliberately stays silent.
        if !NSApplication.shared.isActive {
            remotePushNotifier?.notify(item)
        }

        guard !windowSessionCoordinator.controllers.contains(where: {
            $0.isSurfaceActivelyFocused(event.surfaceID)
        }) else {
            try attentionCenter.acknowledgeActionableItems(for: event.surfaceID)
            return inserted
        }

        guard !windowSessionCoordinator.controllers.contains(where: {
            $0.isSurfaceVisible(event.surfaceID)
        }) else { return inserted }

        attentionNotifier?.notify(item)
        return inserted
    }

    /// Feeds a `CursorApprovalCoordinator`-synthesized event back through
    /// the normal event path. Errors land the same way a real hook
    /// delivery failure would, since there's no hook process left to
    /// report them to.
    private func deliverSyntheticAgentEvent(_ event: AgentEvent) {
        do {
            _ = try receiveAgentEvent(event)
        } catch {
            WindowSessionCoordinator.reportPersistenceError(
                error,
                operation: "agent event"
            )
        }
    }

    private func presentLaunchError(_ error: Error) {
        let alert = ApplicationAlert.make(style: .critical)
        alert.messageText = localizer[.couldNotStart]
        alert.informativeText = String(describing: error)
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }

    private func presentActionError(_ error: Error) {
        let alert = ApplicationAlert.make(style: .critical)
        alert.messageText = localizer[.couldNotCompleteAction]
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

}

private enum TerminalSettingsError: Error {
    case invalidConfiguration([String])
}
