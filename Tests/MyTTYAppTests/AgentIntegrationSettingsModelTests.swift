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
        let model = AgentIntegrationSettingsModel(installer: installer)

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
        let model = AgentIntegrationSettingsModel(installer: installer)

        model.repairInstalledIntegrations()

        #expect(installer.installed == [.codex, .cursor])
        #expect(model.state(for: .codex).status == .installed)
        #expect(model.state(for: .claudeCode).status == .notInstalled)
        #expect(model.state(for: .openCode).status == .installed)
        #expect(model.state(for: .antigravity).status == .notInstalled)
        #expect(model.state(for: .cursor).status == .installed)
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
        let model = AgentIntegrationSettingsModel(installer: installer)

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
}
