import AppKit
import GhosttyAdapter
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Floating pane ASCII input policy")
struct FloatingPaneASCIIInputPolicyTests {
    @Test("stays out of the way when the preference is off")
    func disabledNeverSwitches() {
        #expect(!FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: false,
            scope: .always,
            shellIsFresh: true,
            foregroundCommandName: "zsh"
        ))
    }

    @Test("the always scope switches whatever is running in the panel")
    func alwaysScopeIgnoresForegroundProcess() {
        #expect(FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: true,
            scope: .always,
            shellIsFresh: false,
            foregroundCommandName: "vim"
        ))
    }

    @Test("the idle scope leaves a running process's input source alone")
    func idleScopeSkipsRunningProcess() {
        #expect(!FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: true,
            scope: .shellIdleOnly,
            shellIsFresh: false,
            foregroundCommandName: "vim"
        ))
    }

    @Test("the idle scope switches at a bare prompt")
    func idleScopeSwitchesAtPrompt() {
        #expect(FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: true,
            scope: .shellIdleOnly,
            shellIsFresh: false,
            foregroundCommandName: "zsh"
        ))
    }

    @Test("a just-created shell counts as idle before it can be read")
    func freshShellCountsAsIdle() {
        // The panel's very first open is exactly when this matters -- it's
        // summoned from another app whose IME is active -- and the shell is
        // too young for its foreground process to come back.
        #expect(FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: true,
            scope: .shellIdleOnly,
            shellIsFresh: true,
            foregroundCommandName: nil
        ))
    }

    @Test("an unreadable foreground process in an old shell is left alone")
    func unknownForegroundProcessSkips() {
        #expect(!FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: true,
            scope: .shellIdleOnly,
            shellIsFresh: false,
            foregroundCommandName: nil
        ))
    }
}

@Suite("Floating terminal panel")
struct FloatingTerminalPanelTests {
    @MainActor
    @Test("toggling on creates a live surface and shows the panel")
    func toggleOnShowsPanelAndCreatesSurface() throws {
        let runtime = try Self.makeRuntime()
        let controller = Self.makeController(runtime: runtime)

        #expect(!controller.isPanelVisible)
        #expect(!controller.hasLiveSurface)

        controller.toggle()

        #expect(controller.isPanelVisible)
        #expect(controller.hasLiveSurface)
    }

    @MainActor
    @Test("toggling off slides the panel out and hides it")
    func toggleOffHidesPanel() throws {
        let runtime = try Self.makeRuntime()
        let controller = Self.makeController(runtime: runtime)

        controller.toggle()
        #expect(controller.isPanelVisible)

        controller.toggle()

        #expect(!controller.isPanelVisible)
    }

    @MainActor
    @Test("without a runtime, toggling shows an empty panel but no surface")
    func toggleWithoutRuntimeShowsEmptyPanel() {
        let controller = Self.makeController(runtime: nil)

        controller.toggle()

        #expect(controller.isPanelVisible)
        #expect(!controller.hasLiveSurface)
    }

    @MainActor
    @Test("reopening after a hide reuses the still-live surface")
    func reopenReusesLiveSurface() throws {
        let runtime = try Self.makeRuntime()
        let controller = Self.makeController(runtime: runtime)

        controller.toggle()
        #expect(controller.hasLiveSurface)

        controller.toggle()
        #expect(!controller.isPanelVisible)
        // The shell survives a hide -- only `orderOut` happens, no
        // teardown, so a `childExited` event never fired here.
        #expect(controller.hasLiveSurface)

        controller.toggle()

        #expect(controller.isPanelVisible)
        #expect(controller.hasLiveSurface)
    }

    @MainActor
    @Test("being hidden elsewhere leaves the next hot key press able to reopen")
    func externalHideKeepsTheNextToggleOpening() throws {
        let runtime = try Self.makeRuntime()
        let controller = Self.makeController(runtime: runtime)

        controller.toggle()
        #expect(controller.isPanelVisible)

        controller.simulateExternalHide()
        #expect(!controller.isPanelVisible)

        // Being ordered out sidesteps `toggle()`, so were the open state
        // tracked in a flag of its own this press would be spent sliding
        // out a panel that is already gone.
        controller.toggle()

        #expect(controller.isPanelVisible)
        #expect(controller.hasLiveSurface)
    }

    @MainActor
    @Test("a hide reversed mid-flight by a show discards the stale completion")
    func reversingMidFlightDiscardsStaleCompletion() throws {
        let runtime = try Self.makeRuntime()
        var pendingCompletions: [() -> Void] = []
        let controller = FloatingTerminalPanelController(
            localizer: MyTTYLocalizer(language: .english),
            edge: .top,
            runtimeProvider: { runtime }
        ) { panel, frame, completion in
            panel.setFrame(frame, display: false)
            // Defers the completion instead of calling it immediately, so
            // the test can trigger a second `toggle()` before the first
            // animation "finishes" -- exactly the mid-flight reversal the
            // generation counter exists to handle.
            pendingCompletions.append(completion)
        }

        controller.toggle()
        #expect(pendingCompletions.count == 1)
        controller.toggle()
        #expect(pendingCompletions.count == 2)

        // The first (show) animation's completion is now stale: running it
        // must not make the key/first-responder side effects fire after a
        // hide has already been requested.
        pendingCompletions[0]()
        pendingCompletions[1]()

        #expect(!controller.isPanelVisible)
    }

    @MainActor
    private static func makeController(
        runtime: GhosttyRuntime?
    ) -> FloatingTerminalPanelController {
        FloatingTerminalPanelController(
            localizer: MyTTYLocalizer(language: .english),
            edge: .top,
            runtimeProvider: { runtime },
            frameAnimator: Self.synchronousFrameAnimator
        )
    }

    /// Applies the target frame and calls back immediately -- real slide
    /// timing is `FloatingTerminalPanelController.coreAnimationFrameAnimator`'s
    /// concern (a Core Animation completion callback that rides on an
    /// actual display refresh, unreliable to await on a deadline inside a
    /// headless test process). Injecting this keeps these tests about the
    /// panel's state machine, not about animation timing.
    @MainActor
    private static let synchronousFrameAnimator:
        FloatingTerminalPanelController.FrameAnimator = { panel, frame, completion in
            panel.setFrame(frame, display: false)
            completion()
        }

    @MainActor
    private static func makeRuntime() throws -> GhosttyRuntime {
        try GhosttyLibrary.initializeCurrentProcess()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("terminal.conf")
        try "font-size = 13\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        let configuration = try GhosttyConfiguration(file: file)
        return try GhosttyRuntime(configuration: configuration)
    }
}
