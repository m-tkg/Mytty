import Combine
import Foundation
import MyTTYCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var application: ApplicationPreferences
    @Published private(set) var terminal: TerminalPreferences
    @Published private(set) var terminalThemes: [GhosttyThemePreview]
    @Published private(set) var errorText: MyTTYText?

    var errorMessage: String? {
        errorText.map {
            MyTTYLocalizer(language: application.language)[$0]
        }
    }

    private let paths: ApplicationPaths
    private let applicationStore: ApplicationPreferencesStore
    private let terminalStore: TerminalPreferencesStore
    private let onTerminalConfigurationChanged: (
        TerminalPreferences
    ) throws -> Void
    private let onApplicationPreferencesChanged: (
        ApplicationPreferences
    ) -> Void

    init(
        paths: ApplicationPaths,
        applicationStore: ApplicationPreferencesStore = .init(),
        terminalStore: TerminalPreferencesStore = .init(),
        onTerminalConfigurationChanged: @escaping (
            TerminalPreferences
        ) throws -> Void,
        onApplicationPreferencesChanged: @escaping (
            ApplicationPreferences
        ) -> Void
    ) throws {
        self.paths = paths
        self.applicationStore = applicationStore
        self.terminalStore = terminalStore
        self.onTerminalConfigurationChanged = onTerminalConfigurationChanged
        self.onApplicationPreferencesChanged = onApplicationPreferencesChanged
        application = try applicationStore.load(from: paths.appConfiguration)
        terminal = try terminalStore.load(from: paths.terminalConfiguration)
        terminalThemes = GhosttyThemeCatalog.currentThemes()
    }

    func reload() {
        do {
            application = try applicationStore.load(
                from: paths.appConfiguration
            )
            terminal = try terminalStore.load(
                from: paths.terminalConfiguration
            )
            terminalThemes = GhosttyThemeCatalog.currentThemes()
            errorText = nil
        } catch {
            errorText = .unableToReadSettings
        }
    }

    func setTabPlacement(_ placement: MyTTYTabPlacement) {
        updateApplication { $0.tabPlacement = placement }
    }

    func setKeyBinding(
        _ binding: MyTTYKeyBinding?,
        for command: MyTTYCommand
    ) {
        updateApplication { $0.keyBindings[command] = binding }
    }

    func updateApplication(
        _ update: (inout ApplicationPreferences) -> Void
    ) {
        var updated = application
        update(&updated)
        guard updated != application else { return }
        do {
            try applicationStore.save(updated, to: paths.appConfiguration)
            application = updated
            errorText = nil
            onApplicationPreferencesChanged(updated)
        } catch {
            errorText = .unableToSaveSettings
        }
    }

    func updateTerminal(
        _ update: (inout TerminalPreferences) -> Void
    ) {
        var updated = terminal
        update(&updated)
        guard updated != terminal else { return }

        do {
            let previousData = try Data(
                contentsOf: paths.terminalConfiguration
            )
            try terminalStore.save(updated, to: paths.terminalConfiguration)
            do {
                try onTerminalConfigurationChanged(updated)
            } catch {
                try previousData.write(
                    to: paths.terminalConfiguration,
                    options: .atomic
                )
                throw error
            }
            terminal = updated
            errorText = nil
        } catch {
            errorText = .unableToApplyTerminalSettings
        }
    }
}
