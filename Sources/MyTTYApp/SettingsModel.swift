import Combine
import Foundation
import MyTTYCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var application: ApplicationPreferences
    @Published private(set) var terminal: TerminalPreferences
    @Published private(set) var terminalThemes: [GhosttyThemePreview]
    @Published private(set) var errorText: MyTTYText?
    /// Whether the floating terminal panel's global hot key
    /// (`AppDelegate.registerFloatingPaneHotKey`) failed to register --
    /// typically because another app already owns the combination. Not
    /// persisted: it's a live registration outcome, recomputed on every
    /// preference change, not a stored preference.
    @Published var floatingPaneHotKeyRegistrationFailed = false

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

    @discardableResult
    func reload() -> Bool {
        do {
            let reloadedApplication = try applicationStore.load(
                from: paths.appConfiguration
            )
            let reloadedTerminal = try terminalStore.load(
                from: paths.terminalConfiguration
            )
            try onTerminalConfigurationChanged(reloadedTerminal)
            application = reloadedApplication
            terminal = reloadedTerminal
            terminalThemes = GhosttyThemeCatalog.currentThemes()
            errorText = nil
            onApplicationPreferencesChanged(application)
            return true
        } catch {
            errorText = .unableToReadSettings
            return false
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

    /// Imports the configuration files of another Mytty profile (the
    /// installed release build) and applies them to this one. Returns
    /// whether the import succeeded; failures leave the current settings
    /// files and published values untouched.
    @discardableResult
    func importSettings(from source: ApplicationPaths) -> Bool {
        let previousFiles = [
            paths.appConfiguration,
            paths.terminalConfiguration,
            paths.agentConfiguration,
        ].map { url in
            (url, try? Data(contentsOf: url))
        }
        // Restores every settings file, including after a copy that
        // failed partway through and left only some files overwritten.
        func restorePreviousFiles() {
            for (url, data) in previousFiles {
                if let data {
                    try? data.write(to: url, options: .atomic)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        do {
            _ = try ReleaseSettingsImporter().importSettings(
                from: source,
                to: paths
            )
            let importedApplication = try applicationStore.load(
                from: paths.appConfiguration
            )
            let importedTerminal = try terminalStore.load(
                from: paths.terminalConfiguration
            )
            try onTerminalConfigurationChanged(importedTerminal)
            application = importedApplication
            terminal = importedTerminal
            errorText = nil
            onApplicationPreferencesChanged(application)
            return true
        } catch ReleaseSettingsImporter.ImportError.sourceNotFound {
            errorText = .releaseSettingsNotFound
            return false
        } catch {
            restorePreviousFiles()
            errorText = .unableToImportReleaseSettings
            return false
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
