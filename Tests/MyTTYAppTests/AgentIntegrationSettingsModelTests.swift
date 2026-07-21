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

        model.setInstalled(false, for: .codex)
        model.setInstalled(true, for: .claudeCode)
        model.repair(.openCode)

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

        model.repairInstalledIntegrations()

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

        model.repairInstalledIntegrations()

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

        model.repairInstalledIntegrations()

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

        model.setInstalled(true, for: .claudeCode)

        #expect(installer.pointerInstalled == [.claudeCode])
        #expect(model.paneTeamPointerEnabled == true)

        model.setInstalled(false, for: .claudeCode)

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

        model.setPaneTeamPointerEnabled(false)

        #expect(Set(installer.pointerRemoved) == [.codex, .claudeCode])
        #expect(model.paneTeamPointerEnabled == false)
        #expect(preferenceStore.paneTeamPointersEnabled == false)

        model.setPaneTeamPointerEnabled(true)

        #expect(Set(installer.pointerInstalled) == [.codex, .claudeCode])
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

        #expect(model.paneTeamPointerStatus(for: .codex) == .needsRepair)
        #expect(model.paneTeamPointerStatus(for: .claudeCode) == .notInstalled)
        #expect(model.paneTeamPointerURL(for: .codex) != nil)
        #expect(model.paneTeamPointerURL(for: .cursor) == nil)
        #expect(model.paneTeamPointerPreview(for: .claudeCode) != nil)
        #expect(model.paneTeamPointerPreview(for: .openCode) == nil)
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

        model.setInstalled(true, for: .codex)

        let state = model.state(for: .codex)
        #expect(state.status == .notInstalled)
        #expect(state.errorMessage == "Hook helper is unavailable")
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

    func paneTeamPointerStatus(
        for provider: AgentProvider
    ) throws -> AgentIntegrationStatus {
        pointerStatuses[provider] ?? .notInstalled
    }

    func installPaneTeamPointer(_ provider: AgentProvider) throws {
        pointerInstalled.append(provider)
        pointerStatuses[provider] = .installed
    }

    func removePaneTeamPointer(_ provider: AgentProvider) throws {
        pointerRemoved.append(provider)
        pointerStatuses[provider] = .notInstalled
    }

    func paneTeamPointerURL(for provider: AgentProvider) -> URL? {
        guard AgentIntegrationInstaller.paneTeamPointerProviders
            .contains(provider)
        else { return nil }
        return URL(fileURLWithPath: "/tmp/\(provider.rawValue)-pointer")
    }

    func paneTeamPointerPreview(for provider: AgentProvider) -> String? {
        guard AgentIntegrationInstaller.paneTeamPointerProviders
            .contains(provider)
        else { return nil }
        return "preview for \(provider.rawValue)"
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
