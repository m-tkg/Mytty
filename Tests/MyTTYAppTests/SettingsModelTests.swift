import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Settings model")
struct SettingsModelTests {
    @Test("persists terminal and tab changes before publishing callbacks")
    @MainActor
    func updatesPreferences() throws {
        let harness = try Harness()
        defer { harness.remove() }
        var terminalUpdates: [TerminalPreferences] = []
        var applicationUpdates: [ApplicationPreferences] = []
        let model = try SettingsModel(
            paths: harness.paths,
            onTerminalConfigurationChanged: { terminalUpdates.append($0) },
            onApplicationPreferencesChanged: {
                applicationUpdates.append($0)
            }
        )

        model.updateTerminal { preferences in
            preferences.fontFamily = "JetBrains Mono"
            preferences.fontSize = 16
        }
        model.setTabPlacement(.bottom)
        let newTabBinding = MyTTYKeyBinding(
            key: "x",
            modifiers: [.control]
        )
        model.setKeyBinding(newTabBinding, for: .newTab)
        model.updateApplication { preferences in
            preferences.language = .japanese
            preferences.launchBehavior = .newWindow
            preferences.closeWindowConfirmation = .always
            preferences.closePaneConfirmation = .always
            preferences.closeTabConfirmation = .always
            preferences.confirmClosingLastPane = false
            preferences.windowStartupBehavior = .small
            preferences.showStatusBar = false
            preferences.agentSleepPreventionMode = .preventWhileProcessing
        }

        #expect(model.terminal.fontFamily == "JetBrains Mono")
        #expect(model.terminal.fontSize == 16)
        #expect(model.application.tabPlacement == .bottom)
        #expect(model.errorMessage == nil)
        #expect(terminalUpdates == [model.terminal])
        #expect(applicationUpdates.count == 3)
        #expect(applicationUpdates.last == model.application)
        #expect(model.application.keyBindings[.newTab] == newTabBinding)
        #expect(model.application.language == .japanese)
        #expect(model.application.launchBehavior == .newWindow)
        #expect(model.application.closeWindowConfirmation == .always)
        #expect(model.application.closePaneConfirmation == .always)
        #expect(model.application.closeTabConfirmation == .always)
        #expect(!model.application.confirmClosingLastPane)
        #expect(model.application.windowStartupBehavior == .small)
        #expect(!model.application.showStatusBar)
        #expect(
            model.application.agentSleepPreventionMode
                == .preventWhileProcessing
        )
        #expect(
            try TerminalPreferencesStore()
                .load(from: harness.paths.terminalConfiguration)
                == model.terminal
        )
        #expect(
            try ApplicationPreferencesStore()
                .load(from: harness.paths.appConfiguration)
                == model.application
        )
    }

    @Test("rolls back a terminal file when libghostty rejects reloading it")
    @MainActor
    func reloadFailure() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let original = try Data(contentsOf: harness.paths.terminalConfiguration)
        let model = try SettingsModel(
            paths: harness.paths,
            onTerminalConfigurationChanged: { _ in
                throw TestError.rejected
            },
            onApplicationPreferencesChanged: { _ in }
        )

        model.updateTerminal { $0.fontSize = 18 }

        #expect(model.terminal.fontSize == 13)
        #expect(model.errorMessage == "Unable to apply terminal settings")
        #expect(try Data(contentsOf: harness.paths.terminalConfiguration) == original)
    }
    @Test("imports release settings and publishes them")
    @MainActor
    func importsReleaseSettings() throws {
        let harness = try Harness(profile: .development)
        defer { harness.remove() }
        try harness.writeReleaseSource(
            application: "language = japanese\n",
            terminal: "font-size = 18\n"
        )
        var terminalUpdates: [TerminalPreferences] = []
        var applicationUpdates: [ApplicationPreferences] = []
        let model = try SettingsModel(
            paths: harness.paths,
            onTerminalConfigurationChanged: { terminalUpdates.append($0) },
            onApplicationPreferencesChanged: {
                applicationUpdates.append($0)
            }
        )

        let imported = model.importSettings(from: harness.releaseSource)

        #expect(imported)
        #expect(model.errorMessage == nil)
        #expect(model.application.language == .japanese)
        #expect(model.terminal.fontSize == 18)
        #expect(terminalUpdates == [model.terminal])
        #expect(applicationUpdates == [model.application])
        #expect(
            try ApplicationPreferencesStore()
                .load(from: harness.paths.appConfiguration)
                == model.application
        )
    }

    @Test("reports when no release settings exist")
    @MainActor
    func importWithoutReleaseSettings() throws {
        let harness = try Harness(profile: .development)
        defer { harness.remove() }
        let model = try SettingsModel(
            paths: harness.paths,
            onTerminalConfigurationChanged: { _ in },
            onApplicationPreferencesChanged: { _ in }
        )

        let imported = model.importSettings(from: harness.releaseSource)

        #expect(!imported)
        #expect(model.errorMessage == "No Mytty release settings were found")
    }

    @Test("rolls back an import when libghostty rejects the terminal file")
    @MainActor
    func importRollsBackOnTerminalRejection() throws {
        let harness = try Harness(profile: .development)
        defer { harness.remove() }
        try harness.writeReleaseSource(
            application: "language = japanese\n",
            terminal: "font-size = 18\n"
        )
        let originalTerminal = try Data(
            contentsOf: harness.paths.terminalConfiguration
        )
        let originalApplication = try Data(
            contentsOf: harness.paths.appConfiguration
        )
        let model = try SettingsModel(
            paths: harness.paths,
            onTerminalConfigurationChanged: { _ in
                throw TestError.rejected
            },
            onApplicationPreferencesChanged: { _ in }
        )

        let imported = model.importSettings(from: harness.releaseSource)

        #expect(!imported)
        #expect(model.errorMessage == "Unable to import release settings")
        #expect(model.application.language == .systemDefault)
        #expect(model.terminal.fontSize == 13)
        #expect(
            try Data(contentsOf: harness.paths.terminalConfiguration)
                == originalTerminal
        )
        #expect(
            try Data(contentsOf: harness.paths.appConfiguration)
                == originalApplication
        )
    }
}

private enum TestError: Error {
    case rejected
}

private struct Harness {
    let root: URL
    let paths: ApplicationPaths
    let releaseSource: ApplicationPaths

    init(profile: ApplicationPathProfile = .release) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: root.appendingPathComponent("tmp"),
            profile: profile
        )
        releaseSource = ApplicationPaths(
            homeDirectory: root,
            temporaryDirectory: root.appendingPathComponent("tmp"),
            profile: .release
        )
        try ApplicationFileSystem().prepare(paths)
    }

    func writeReleaseSource(
        application: String,
        terminal: String
    ) throws {
        try FileManager.default.createDirectory(
            at: releaseSource.configurationDirectory,
            withIntermediateDirectories: true
        )
        try application.write(
            to: releaseSource.appConfiguration,
            atomically: true,
            encoding: .utf8
        )
        try terminal.write(
            to: releaseSource.terminalConfiguration,
            atomically: true,
            encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
