import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsModel: SettingsModel
    private let integrationsModel: AgentIntegrationSettingsModel
    private let defaultTerminalModel: DefaultTerminalModel
    private let commandLineToolInstallModel: CommandLineToolInstallModel
    private let remoteAccessModel: RemoteAccessSettingsModel

    init(
        settingsModel: SettingsModel,
        integrationsModel: AgentIntegrationSettingsModel,
        updateModel: ApplicationUpdateModel,
        defaultTerminalModel: DefaultTerminalModel,
        commandLineToolInstallModel: CommandLineToolInstallModel,
        remoteAccessModel: RemoteAccessSettingsModel
    ) {
        self.settingsModel = settingsModel
        self.integrationsModel = integrationsModel
        self.defaultTerminalModel = defaultTerminalModel
        self.commandLineToolInstallModel = commandLineToolInstallModel
        self.remoteAccessModel = remoteAccessModel
        let view = SettingsView(
            settings: settingsModel,
            integrations: integrationsModel,
            updates: updateModel,
            defaultTerminal: defaultTerminalModel,
            commandLineToolInstall: commandLineToolInstallModel,
            remoteAccess: remoteAccessModel
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = MyTTYLocalizer(
            language: settingsModel.application.language
        )[.myTTYSettings]
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.setFrameAutosaveName("mytty.settings")
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        settingsModel.reload()
        updateLocalization(
            MyTTYLocalizer(language: settingsModel.application.language)
        )
        integrationsModel.refresh()
        defaultTerminalModel.refresh()
        commandLineToolInstallModel.refresh()
        remoteAccessModel.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func updateLocalization(_ localizer: MyTTYLocalizer) {
        window?.title = localizer[.myTTYSettings]
    }

    // A pairing code is only meaningful while its Settings pane is on
    // screen: leaving one active after the window closes keeps the server
    // accepting pair requests the user can no longer see or cancel.
    func windowWillClose(_ notification: Notification) {
        remoteAccessModel.cancelPairing()
    }
}
