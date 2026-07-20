import Combine
import Foundation
import MyTTYCore

@MainActor
protocol AgentIntegrationInstalling {
    func status(for provider: AgentProvider) throws -> AgentIntegrationStatus
    func install(_ provider: AgentProvider) throws
    func remove(_ provider: AgentProvider) throws
}

extension AgentIntegrationInstaller: AgentIntegrationInstalling {}

struct AgentIntegrationSettingsState: Equatable, Identifiable {
    let provider: AgentProvider
    var status: AgentIntegrationStatus
    var errorText: MyTTYText?

    var id: AgentProvider { provider }
    var errorMessage: String? { errorText?.rawValue }

    init(
        provider: AgentProvider,
        status: AgentIntegrationStatus,
        errorMessage: String?
    ) {
        self.provider = provider
        self.status = status
        errorText = errorMessage.flatMap(MyTTYText.init(rawValue:))
    }

    var guidance: String? {
        guard provider == .codex, status == .installed else { return nil }
        return "Restart Codex, then run /hooks. Open each event, select "
            + "mytty-agent-hook, and approve it if needed until Trust says Trusted."
    }
}

@MainActor
final class AgentIntegrationSettingsModel: ObservableObject {
    @Published private(set) var states: [AgentIntegrationSettingsState]

    private let installer: any AgentIntegrationInstalling

    init(installer: any AgentIntegrationInstalling) {
        self.installer = installer
        states = Self.providers.map {
            AgentIntegrationSettingsState(
                provider: $0,
                status: .notInstalled,
                errorMessage: nil
            )
        }
        refresh()
    }

    func state(
        for provider: AgentProvider
    ) -> AgentIntegrationSettingsState {
        states.first(where: { $0.provider == provider })
            ?? AgentIntegrationSettingsState(
                provider: provider,
                status: .notInstalled,
                errorMessage: nil
            )
    }

    func refresh() {
        for provider in Self.providers {
            refresh(provider)
        }
    }

    func repairInstalledIntegrations() {
        for provider in Self.providers
        where state(for: provider).status == .needsRepair {
            do {
                try installer.install(provider)
                refresh(provider)
            } catch {
                setError(text(for: error), for: provider)
            }
        }
    }

    func setInstalled(_ installed: Bool, for provider: AgentProvider) {
        do {
            if installed {
                try installer.install(provider)
            } else {
                try installer.remove(provider)
            }
            refresh(provider)
        } catch {
            setError(text(for: error), for: provider)
        }
    }

    func repair(_ provider: AgentProvider) {
        setInstalled(true, for: provider)
    }

    private func refresh(_ provider: AgentProvider) {
        do {
            setState(
                status: try installer.status(for: provider),
                errorText: nil,
                for: provider
            )
        } catch {
            setError(text(for: error), for: provider)
        }
    }

    private func setError(_ text: MyTTYText, for provider: AgentProvider) {
        setState(
            status: state(for: provider).status,
            errorText: text,
            for: provider
        )
    }

    private func setState(
        status: AgentIntegrationStatus,
        errorText: MyTTYText?,
        for provider: AgentProvider
    ) {
        guard let index = states.firstIndex(where: {
            $0.provider == provider
        }) else { return }
        states[index].status = status
        states[index].errorText = errorText
    }

    private func text(for error: Error) -> MyTTYText {
        switch error {
        case AgentIntegrationInstallerError.missingHookExecutable:
            .hookHelperUnavailable
        case AgentIntegrationInstallerError.invalidConfiguration:
            .invalidProviderConfiguration
        default:
            .unableToUpdateIntegration
        }
    }

    private static let providers: [AgentProvider] = [
        .codex,
        .claudeCode,
        .openCode,
        .antigravity,
        .cursor,
    ]
}
