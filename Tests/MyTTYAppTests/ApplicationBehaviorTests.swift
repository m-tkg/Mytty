import AppKit
import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Application behavior")
struct ApplicationBehaviorTests {
    @Test("closes settings after the final terminal window closes")
    func auxiliaryWindowLifecycle() {
        #expect(
            ApplicationWindowLifecycle.shouldCloseSettings(
                remainingTerminalWindowCount: 0
            )
        )
        #expect(
            !ApplicationWindowLifecycle.shouldCloseSettings(
                remainingTerminalWindowCount: 1
            )
        )
    }

    @Test("uses a distinct identity for local debug builds")
    func debugApplicationIdentity() {
        #expect(ApplicationIdentity.displayName == "Mytty Dev")
        #expect(ApplicationIdentity.bundleIdentifier == "com.m-tkg.mytty.dev")
        #expect(ApplicationIdentity.pathProfile == .development)
        #expect(ApplicationIdentity.dockBadge == "DEV")
        #expect(!ApplicationIdentity.supportsSelfUpdate)
    }

    @Test("restores sessions only when the launch setting permits it")
    func launchSessions() {
        let session = makeSession()

        #expect(
            ApplicationLaunchPolicy.sessionsToRestore(
                [session],
                behavior: .restoreLastSession
            ) == [session]
        )
        #expect(
            ApplicationLaunchPolicy.sessionsToRestore(
                [session],
                behavior: .newWindow
            ).isEmpty
        )
    }

    @Test("starts a new session in the home directory")
    func initialWorkingDirectory() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let launchServicesDirectory = URL(
            fileURLWithPath: "/",
            isDirectory: true
        )

        #expect(
            ApplicationLaunchPolicy.initialWorkingDirectory(
                homeDirectory: home,
                processDirectory: launchServicesDirectory
            ) == home
        )
    }

    @Test("preserves the final window snapshot while the app terminates")
    func terminationPersistence() {
        let state = ApplicationTerminationState()

        #expect(state.beginTermination())
        #expect(!state.shouldSaveAfterWindowRemoval)
        #expect(!state.beginTermination())
    }

    @Test("plans remembered, fullscreen, and small windows centered on the target screen")
    func windowPlans() {
        let remembered = WindowFrame(
            x: 10,
            y: 20,
            width: 1234,
            height: 777
        )
        let fallback = WindowFrame(
            x: 160,
            y: 140,
            width: 1100,
            height: 720
        )
        let maximum = WindowFrame(
            x: 0,
            y: 25,
            width: 1512,
            height: 957
        )

        let restored = WindowStartupPlan.make(
            behavior: .rememberLastSize,
            rememberedFrame: remembered,
            fallbackFrame: fallback,
            maximumFrame: maximum
        )
        #expect(restored.frame.width == 1234)
        #expect(restored.frame.height == 777)
        #expect(restored.frame.x == 139)
        #expect(restored.frame.y == 115)

        let fullscreen = WindowStartupPlan.make(
            behavior: .fullscreen,
            rememberedFrame: remembered,
            fallbackFrame: fallback,
            maximumFrame: maximum
        )
        #expect(fullscreen.frame == maximum)

        let small = WindowStartupPlan.make(
            behavior: .small,
            rememberedFrame: remembered,
            fallbackFrame: fallback,
            maximumFrame: maximum
        )
        #expect(small.frame.width == 820)
        #expect(small.frame.height == 520)
        #expect(small.frame.x == 346)
        #expect(small.frame.y == 243.5)

        let noRemembered = WindowStartupPlan.make(
            behavior: .rememberLastSize,
            rememberedFrame: nil,
            fallbackFrame: fallback,
            maximumFrame: maximum
        )
        #expect(noRemembered.frame.width == fallback.width)
        #expect(noRemembered.frame.height == fallback.height)
        #expect(noRemembered.frame.x == 206)
        #expect(noRemembered.frame.y == 143.5)
    }

    @Test("selects confirmation policies by close target")
    func closePolicies() {
        let preferences = ApplicationPreferences(
            closeWindowConfirmation: .always,
            closePaneConfirmation: .whenProcessRunning,
            closeTabConfirmation: .always
        )

        #expect(
            preferences.confirmation(for: .window)
                == .always
        )
        #expect(
            preferences.confirmation(for: .pane)
                == .whenProcessRunning
        )
        #expect(
            preferences.confirmation(for: .tab)
                == .always
        )
    }

    @Test("routes shell exits through the matching confirmed close path")
    func shellExitCloseActions() {
        #expect(
            TerminalExitCloseAction.make(
                processAlive: true,
                paneCount: 1,
                tabCount: 1
            ) == .ignore
        )
        #expect(
            TerminalExitCloseAction.make(
                processAlive: false,
                paneCount: 2,
                tabCount: 1
            ) == .closePane(requiresConfirmation: true)
        )
        #expect(
            TerminalExitCloseAction.make(
                processAlive: false,
                paneCount: 1,
                tabCount: 2
            ) == .closeTab(requiresConfirmation: true)
        )
        #expect(
            TerminalExitCloseAction.make(
                processAlive: false,
                paneCount: 1,
                tabCount: 1
            ) == .closeLastPane
        )
    }

    @Test("restarts an exited surface when close confirmation is cancelled")
    func cancelledShellExitClose() {
        #expect(
            TerminalExitedSurfaceCloseResolution.make(
                requiresConfirmation: true,
                confirmed: false
            ) == .restartSurface
        )
        #expect(
            TerminalExitedSurfaceCloseResolution.make(
                requiresConfirmation: true,
                confirmed: true
            ) == .close
        )
        #expect(
            TerminalExitedSurfaceCloseResolution.make(
                requiresConfirmation: false,
                confirmed: false
            ) == .close
        )
    }

    @Test("distinguishes a pane close that would close every tab")
    func paneCloseActions() {
        #expect(
            TerminalPaneCloseAction.make(
                paneCount: 2,
                tabCount: 1
            ) == .closePane
        )
        #expect(
            TerminalPaneCloseAction.make(
                paneCount: 1,
                tabCount: 2
            ) == .closeTab
        )
        #expect(
            TerminalPaneCloseAction.make(
                paneCount: 1,
                tabCount: 1
            ) == .closeLastPane
        )
    }

    @Test("explains that closing the last pane closes every tab")
    @MainActor
    func lastPaneCloseAlert() throws {
        let alert = TerminalWindowController.makeLastPaneCloseConfirmationAlert(
            hasRunningProcess: true,
            localizer: MyTTYLocalizer(language: .english)
        )
        let applicationIcon = try #require(ApplicationIcon.image)

        #expect(alert.messageText == "Close the last pane?")
        #expect(alert.informativeText.contains(
            "This will close all tabs in this window."
        ))
        #expect(alert.informativeText.contains(
            "A process is still running in this terminal."
        ))
        #expect(
            alert.icon?.tiffRepresentation
                == applicationIcon.tiffRepresentation
        )
    }

    @Test("uses the application icon in close confirmation alerts")
    @MainActor
    func closeConfirmationAlertIcon() throws {
        let alert = TerminalWindowController.makeCloseConfirmationAlert(
            target: .pane,
            hasRunningProcess: false,
            localizer: MyTTYLocalizer(language: .english)
        )
        let applicationIcon = try #require(ApplicationIcon.image)

        #expect(
            alert.icon?.tiffRepresentation
                == applicationIcon.tiffRepresentation
        )
    }

    @Test("uses the application icon in tab rename alerts")
    @MainActor
    func renameTabAlertIcon() throws {
        let alert = TerminalWindowController.makeRenameTabAlert(
            currentTitle: "Build logs",
            localizer: MyTTYLocalizer(language: .english)
        )
        let applicationIcon = try #require(ApplicationIcon.image)

        #expect(
            alert.icon?.tiffRepresentation
                == applicationIcon.tiffRepresentation
        )
        #expect((alert.accessoryView as? NSTextField)?.stringValue == "Build logs")
    }

    @Test("uses the application icon in shared application alerts")
    @MainActor
    func sharedApplicationAlertIcon() throws {
        let alert = ApplicationAlert.make(style: .critical)
        let applicationIcon = try #require(ApplicationIcon.image)

        #expect(alert.alertStyle == .critical)
        #expect(
            alert.icon?.tiffRepresentation
                == applicationIcon.tiffRepresentation
        )
    }

    @Test("converts a saved window frame without changing its outer size")
    @MainActor
    func savedWindowFrameConversion() {
        let savedFrame = NSRect(x: 100, y: 120, width: 1234, height: 777)

        let contentRect = TerminalWindowGeometry.contentRect(
            forWindowFrame: savedFrame
        )
        let restoredFrame = NSWindow.frameRect(
            forContentRect: contentRect,
            styleMask: TerminalWindowGeometry.styleMask
        )

        #expect(restoredFrame == savedFrame)
    }

    @Test("reapplies a saved frame after configuring window content")
    @MainActor
    func reappliesSavedWindowFrame() {
        let savedFrame = NSRect(x: 100, y: 120, width: 1234, height: 777)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 400),
            styleMask: TerminalWindowGeometry.styleMask,
            backing: .buffered,
            defer: false
        )

        TerminalWindowGeometry.apply(savedFrame, to: window)

        #expect(window.frame == savedFrame)
    }

    private func makeSession() -> WindowSession {
        let surface = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let tab = TabSession(initialSurface: surface)
        return WindowSession(
            frame: WindowFrame(x: 10, y: 20, width: 900, height: 600),
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    @Test("accepts browser-only sessions for restoration")
    func restoresBrowserOnlySession() {
        let browser = BrowserPaneState(
            url: URL(fileURLWithPath: "/tmp/index.html")
        )
        let tab = TabSession(initialBrowser: browser)
        let window = WindowSession(
            frame: WindowFrame(x: 10, y: 20, width: 900, height: 600),
            tabs: [tab],
            selectedTabID: tab.id
        )

        #expect(window.isStructurallyRestorable)
    }
}
