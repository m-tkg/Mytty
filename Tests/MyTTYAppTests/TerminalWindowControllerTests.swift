import AppKit
import GhosttyAdapter
import MyTTYCore
import Testing

@testable import MyTTYApp

/// Regression coverage for the incident that motivated
/// `fix/non-modal-dialogs`: an orchestrated `agent spawn` whose surface
/// creation failed used to call `presentActionError`, whose
/// `NSAlert.runModal()` blocked the main actor `ControlServer` answers
/// every `mytty-ctl` request on -- freezing the control socket for ~1.5
/// hours until a human clicked the alert's OK button. `splitPaneInBackground`
/// now logs and returns nil instead of presenting anything, so this test
/// drives a real `TerminalWindowController` (via an injected failing
/// `surfaceFactory`, the smallest seam `makeSurface` offered) and checks
/// both halves: the orchestrated split reports failure, and no dialog --
/// sheet or otherwise -- ever attaches to the window.
@Suite("Terminal window controller orchestrated split failure", .serialized)
struct TerminalWindowControllerTests {
    @Test("an orchestrated split whose surface creation fails returns nil and presents no dialog")
    @MainActor
    func orchestratedSplitFailureShowsNoDialog() throws {
        let controller = try Self.makeController()
        defer { controller.window?.close() }

        let anchorPaneID = try #require(
            controller.session.selectedTab?.focusedSurfaceID
        )

        // Real pane creation succeeded during `init` (using the real
        // factory); now fail every *subsequent* creation, which is what
        // an orchestrated `mytty-ctl split` / `agent spawn` triggers.
        controller.surfaceFactory = { _, _, _ in
            throw TerminalWindowControllerTestsFailure.surfaceCreationFailed
        }

        let newPaneID = controller.splitPane(
            anchorPaneID,
            direction: .right,
            orchestrated: true
        )

        #expect(newPaneID == nil)
        // The only pane is still the one from `init` -- the failed split
        // added nothing to the session.
        #expect(controller.session.tabs.flatMap(\.surfaceIDs) == [anchorPaneID])
        // The whole point: no sheet (or any other dialog) ever attaches
        // to the window over a background pane the human never asked to
        // see, and nothing here blocked waiting on one either -- this
        // assertion runs immediately, synchronously, after `splitPane`
        // returns.
        #expect(controller.window?.attachedSheet == nil)
    }

    @MainActor
    private static func makeController() throws -> TerminalWindowController {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try GhosttyLibrary.initializeCurrentProcess()
        let confFile = directory.appendingPathComponent("terminal.conf")
        // `zsh -f` keeps the test shell away from the developer's rc files
        // and real `~/.zsh_history` (see GhosttySurfaceIntegrationTests).
        try "font-size = 13\ncommand = direct:/bin/zsh -f\n".write(
            to: confFile,
            atomically: true,
            encoding: .utf8
        )
        let runtime = try GhosttyRuntime(
            configuration: try GhosttyConfiguration(file: confFile)
        )

        let repository = SQLiteAgentEventRepository(
            databaseURL: directory.appendingPathComponent("events.sqlite")
        )
        let attentionCenter = AttentionCenter(repository: repository)
        let agentEventServer = AgentEventServer(
            socketURL: directory.appendingPathComponent("mytty.sock"),
            aiControlSocketURL: directory
                .appendingPathComponent("mytty-ctl.sock"),
            aiControlExecutableURL: directory
                .appendingPathComponent("mytty-ctl"),
            inheritedSearchPath: "/usr/bin:/bin",
            onEvent: { _ in false },
            onError: { _ in }
        )
        let paneInputScheduler = PaneInputScheduler(
            repository: SQLitePaneInputScheduleRepository(
                databaseURL: directory.appendingPathComponent("schedules.sqlite")
            ),
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        let remoteConnections = RemotePaneConnectionCoordinator(
            store: RemoteHostStore(
                fileURL: directory.appendingPathComponent("remote-hosts.json")
            ),
            paneFont: NSFont.systemFont(ofSize: 13),
            onError: { _ in }
        )

        let initialState = TerminalSurfaceState(workingDirectory: directory)
        let initialTab = TabSession(initialSurface: initialState)
        let session = WindowSession(
            frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
            tabs: [initialTab],
            selectedTabID: initialTab.id
        )

        return try TerminalWindowController(
            session: session,
            runtime: runtime,
            attentionCenter: attentionCenter,
            agentEventServer: agentEventServer,
            paneInputScheduler: paneInputScheduler,
            applicationPreferences: ApplicationPreferences(),
            tabDragCoordinator: TabDragCoordinator(),
            closedPaneHistory: ClosedPaneHistory(),
            remoteConnections: remoteConnections,
            onSessionChanged: { _ in },
            onWindowClosed: { _ in },
            onNewWindowRequested: { _ in },
            onFocusSurfaceRequested: { _ in },
            onAgentActivityChanged: {},
            onSleepPreventionModeSelected: { _ in },
            onTabDropRequested: { _ in },
            onTabDragSessionEnded: { _, _ in }
        )
    }
}

private enum TerminalWindowControllerTestsFailure: Error {
    case surfaceCreationFailed
}
