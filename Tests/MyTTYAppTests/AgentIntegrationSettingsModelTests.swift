import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Agent integration settings model")
struct AgentIntegrationSettingsModelTests {
    @Test("shows hook trust guidance only for an installed Codex integration")
    func codexTrustGuidance() {
        let installed = AgentIntegrationSettingsState(
            provider: .codex,
            status: .installed,
            errorMessage: nil
        )
        let absent = AgentIntegrationSettingsState(
            provider: .codex,
            status: .notInstalled,
            errorMessage: nil
        )
        let claude = AgentIntegrationSettingsState(
            provider: .claudeCode,
            status: .installed,
            errorMessage: nil
        )

        #expect(installed.guidance?.contains("/hooks") == true)
        #expect(installed.guidance?.contains("Restart Codex") == true)
        #expect(installed.guidance?.contains("Trust says Trusted") == true)
        #expect(absent.guidance == nil)
        #expect(claude.guidance == nil)
    }

    @Test("refreshes provider state and routes toggle actions")
    @MainActor
    func toggleActions() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .installed,
            .claudeCode: .notInstalled,
            .openCode: .needsRepair,
            .antigravity: .notInstalled,
            .cursor: .installed,
        ])
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        #expect(model.state(for: .codex).status == .installed)
        #expect(model.state(for: .claudeCode).status == .notInstalled)
        #expect(model.state(for: .openCode).status == .needsRepair)
        #expect(model.state(for: .antigravity).status == .notInstalled)
        #expect(model.state(for: .cursor).status == .installed)
        #expect(model.states.count == 5)

        model.setInstalled(false, for: .codex, language: .english)
        model.setInstalled(true, for: .claudeCode, language: .english)
        model.repair(.openCode, language: .english)

        #expect(installer.removed == [.codex])
        #expect(installer.installed == [.claudeCode, .openCode])
        #expect(model.state(for: .codex).status == .notInstalled)
        #expect(model.state(for: .claudeCode).status == .installed)
        #expect(model.state(for: .openCode).status == .installed)
    }

    @Test("repairs only previously installed integrations during migration")
    @MainActor
    func repairInstalledIntegrations() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .needsRepair,
            .claudeCode: .notInstalled,
            .openCode: .installed,
            .antigravity: .notInstalled,
            .cursor: .needsRepair,
        ])
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        model.repairInstalledIntegrations(language: .english)

        #expect(installer.installed == [.codex, .cursor])
        #expect(model.state(for: .codex).status == .installed)
        #expect(model.state(for: .claudeCode).status == .notInstalled)
        #expect(model.state(for: .openCode).status == .installed)
        #expect(model.state(for: .antigravity).status == .notInstalled)
        #expect(model.state(for: .cursor).status == .installed)
        // Codex went from needsRepair to installed above, and its pointer
        // was never written (the default pointerStatuses entry), so repair
        // backfills it. claudeCode stays untouched because its hook is
        // still notInstalled.
        #expect(installer.pointerInstalled == [.codex])
    }

    @Test("backfills the pane-team pointer for providers installed before the preference existed")
    @MainActor
    func repairBackfillsPointerForAlreadyInstalledProviders() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .installed,
            .claudeCode: .installed,
            .openCode: .notInstalled,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        // No pointerStatuses entries for either provider: both supported
        // hooks are already installed, but no pointer has ever been
        // written -- the state an existing user is in right after
        // updating to a build with this feature.
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        model.repairInstalledIntegrations(language: .english)

        #expect(Set(installer.pointerInstalled) == [.codex, .claudeCode])
    }

    @Test("leaves the pane-team pointer untouched during repair when the preference is off")
    @MainActor
    func repairSkipsPointerWhenPreferenceDisabled() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .installed,
            .claudeCode: .installed,
            .openCode: .notInstalled,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore(
                paneTeamPointersEnabled: false
            )
        )

        model.repairInstalledIntegrations(language: .english)

        #expect(installer.pointerInstalled.isEmpty)
        #expect(model.paneTeamPointerEnabled == false)
    }

    @Test("shows the pane-team pointer toggle on even when the pointer hasn't reached disk yet")
    @MainActor
    func paneTeamPointerToggleReflectsPreferenceNotDiskState() {
        // Reproduces the real-world regression: both supported providers'
        // hooks are Installed, but neither pointer has been written (no
        // pointerStatuses entries). The toggle must still read on because
        // it's backed by the persisted preference, not derived from the
        // pointer files' absence.
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .installed,
            .claudeCode: .installed,
            .openCode: .notInstalled,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        #expect(model.paneTeamPointerEnabled == true)
    }

    @Test("defaults the pane-team pointer toggle on before any provider is installed")
    @MainActor
    func paneTeamPointerDefaultsOn() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .notInstalled,
            .claudeCode: .notInstalled,
            .openCode: .notInstalled,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        #expect(model.paneTeamPointerEnabled == true)
    }

    @Test("installing a supported provider also installs its pane-team pointer by default")
    @MainActor
    func paneTeamPointerFollowsProviderInstall() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .notInstalled,
            .claudeCode: .notInstalled,
            .openCode: .notInstalled,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        model.setInstalled(true, for: .claudeCode, language: .japanese)

        #expect(installer.pointerInstalled == [.claudeCode])
        #expect(installer.pointerLanguages[.claudeCode] == .japanese)
        #expect(model.paneTeamPointerEnabled == true)

        model.setInstalled(false, for: .claudeCode, language: .japanese)

        #expect(installer.pointerRemoved == [.claudeCode])
    }

    @Test("toggling the pane-team pointer only touches installed, supported providers")
    @MainActor
    func paneTeamPointerToggle() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .installed,
            .claudeCode: .installed,
            .openCode: .installed,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        let preferenceStore = FakePaneTeamPointerPreferenceStore()
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: preferenceStore
        )

        model.setPaneTeamPointerEnabled(false, language: .english)

        #expect(Set(installer.pointerRemoved) == [.codex, .claudeCode])
        #expect(model.paneTeamPointerEnabled == false)
        #expect(preferenceStore.paneTeamPointersEnabled == false)

        model.setPaneTeamPointerEnabled(true, language: .japanese)

        #expect(Set(installer.pointerInstalled) == [.codex, .claudeCode])
        #expect(installer.pointerLanguages[.codex] == .japanese)
        #expect(installer.pointerLanguages[.claudeCode] == .japanese)
        #expect(model.paneTeamPointerEnabled == true)
        #expect(preferenceStore.paneTeamPointersEnabled == true)
    }

    @Test("exposes pane-team pointer URL, preview, and status for the Orchestration section")
    @MainActor
    func paneTeamPointerDisplayInfo() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .installed,
            .claudeCode: .installed,
            .openCode: .notInstalled,
            .antigravity: .notInstalled,
            .cursor: .notInstalled,
        ])
        installer.pointerStatuses[.codex] = .needsRepair
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        #expect(
            model.paneTeamPointerStatus(for: .codex, language: .english)
                == .needsRepair
        )
        #expect(
            model.paneTeamPointerStatus(for: .claudeCode, language: .english)
                == .notInstalled
        )
        #expect(model.paneTeamPointerURL(for: .codex) != nil)
        #expect(model.paneTeamPointerURL(for: .cursor) == nil)
        #expect(
            model.paneTeamPointerPreview(for: .claudeCode, language: .english)
                != nil
        )
        #expect(
            model.paneTeamPointerPreview(for: .openCode, language: .english)
                == nil
        )
        // The preview text itself carries the requested language through
        // to the installer, not just the status/install calls.
        #expect(
            model.paneTeamPointerPreview(for: .claudeCode, language: .japanese)
                == "preview for claude-code in japanese"
        )
    }

    @Test("keeps a provider error visible without changing its state")
    @MainActor
    func actionError() {
        let installer = FakeAgentIntegrationInstaller(statuses: [
            .codex: .notInstalled,
            .claudeCode: .notInstalled,
            .openCode: .notInstalled,
        ])
        installer.installError = .missingHookExecutable("/missing/helper")
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        model.setInstalled(true, for: .codex, language: .english)

        let state = model.state(for: .codex)
        #expect(state.status == .notInstalled)
        #expect(state.errorMessage == "Hook helper is unavailable")
    }

    // This exercises the actual on-disk write path with the real
    // `AgentIntegrationInstaller` (in a temp home directory, never the
    // developer's real `~/.claude`/`~/.codex`), standing in for the
    // Settings-window flow: AppDelegate's `applyApplicationPreferences`
    // calls `repairInstalledIntegrations(language:)` on every application
    // preference change, including a language switch made while the
    // Orchestration section is open. It isn't practical to drive
    // `AppDelegate`/`NSApplication` from a unit test, so this reproduces
    // that call sequence directly against the model.
    @Test("rewrites the pane-team pointer in the new language when repaired after a live language switch")
    @MainActor
    func repairRewritesPointerAfterLiveLanguageSwitch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let sourceExecutable = root
            .appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent("mytty-agent-hook")
        try FileManager.default.createDirectory(
            at: sourceExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test helper".utf8).write(to: sourceExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sourceExecutable.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = AgentIntegrationInstaller(
            homeDirectory: home,
            applicationSupportDirectory: home
                .appendingPathComponent(
                    "Library/Application Support/mytty",
                    isDirectory: true
                ),
            sourceHookExecutable: sourceExecutable
        )
        let model = AgentIntegrationSettingsModel(
            installer: installer,
            preferenceStore: FakePaneTeamPointerPreferenceStore()
        )

        // Settings > Agents: enable Claude Code while the app is in
        // English, same as `setInstalled` wired from
        // `AgentIntegrationSettingsView`.
        model.setInstalled(true, for: .claudeCode, language: .english)
        #expect(
            model.paneTeamPointerStatus(for: .claudeCode, language: .english)
                == .installed
        )
        let skillURL = try #require(
            model.paneTeamPointerURL(for: .claudeCode)
        )
        let englishContent = try String(
            contentsOf: skillURL,
            encoding: .utf8
        )
        #expect(!englishContent.contains("ペイン"))

        // The user flips Settings > General > Language to Japanese. Status
        // against the new language reads as needing repair even though
        // nothing has been reinstalled yet.
        #expect(
            model.paneTeamPointerStatus(for: .claudeCode, language: .japanese)
                == .needsRepair
        )

        // AppDelegate.applyApplicationPreferences calling
        // repairInstalledIntegrations(language:) on every preference
        // change is what makes that repair happen without a restart.
        model.repairInstalledIntegrations(language: .japanese)

        #expect(
            model.paneTeamPointerStatus(for: .claudeCode, language: .japanese)
                == .installed
        )
        let japaneseContent = try String(
            contentsOf: skillURL,
            encoding: .utf8
        )
        #expect(japaneseContent.contains("ペイン"))
        #expect(japaneseContent.contains("name: mytty-panes"))
        #expect(japaneseContent.contains("$MYTTY_CTL_BIN\" guide"))
    }
}

@MainActor
private final class FakeAgentIntegrationInstaller: AgentIntegrationInstalling {
    var statuses: [AgentProvider: AgentIntegrationStatus]
    var installed: [AgentProvider] = []
    var removed: [AgentProvider] = []
    var installError: AgentIntegrationInstallerError?

    var pointerStatuses: [AgentProvider: AgentIntegrationStatus] = [:]
    var pointerInstalled: [AgentProvider] = []
    var pointerRemoved: [AgentProvider] = []

    init(statuses: [AgentProvider: AgentIntegrationStatus]) {
        self.statuses = statuses
    }

    func status(for provider: AgentProvider) throws -> AgentIntegrationStatus {
        statuses[provider] ?? .notInstalled
    }

    func install(_ provider: AgentProvider) throws {
        if let installError { throw installError }
        installed.append(provider)
        statuses[provider] = .installed
    }

    func remove(_ provider: AgentProvider) throws {
        removed.append(provider)
        statuses[provider] = .notInstalled
    }

    var pointerLanguages: [AgentProvider: PaneTeamPointerLanguage] = [:]

    func paneTeamPointerStatus(
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) throws -> AgentIntegrationStatus {
        pointerStatuses[provider] ?? .notInstalled
    }

    func installPaneTeamPointer(
        _ provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) throws {
        pointerInstalled.append(provider)
        pointerStatuses[provider] = .installed
        pointerLanguages[provider] = language
    }

    func removePaneTeamPointer(_ provider: AgentProvider) throws {
        pointerRemoved.append(provider)
        pointerStatuses[provider] = .notInstalled
        pointerLanguages.removeValue(forKey: provider)
    }

    func paneTeamPointerURL(for provider: AgentProvider) -> URL? {
        guard AgentIntegrationInstaller.paneTeamPointerProviders
            .contains(provider)
        else { return nil }
        return URL(fileURLWithPath: "/tmp/\(provider.rawValue)-pointer")
    }

    func paneTeamPointerPreview(
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) -> String? {
        guard AgentIntegrationInstaller.paneTeamPointerProviders
            .contains(provider)
        else { return nil }
        return "preview for \(provider.rawValue) in \(language)"
    }
}

@MainActor
private final class FakePaneTeamPointerPreferenceStore:
    PaneTeamPointerPreferenceStoring {
    var paneTeamPointersEnabled: Bool

    init(paneTeamPointersEnabled: Bool = true) {
        self.paneTeamPointersEnabled = paneTeamPointersEnabled
    }
}
