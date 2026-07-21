import Combine
import Foundation
import MyTTYCore

@MainActor
protocol AgentIntegrationInstalling {
    func status(for provider: AgentProvider) throws -> AgentIntegrationStatus
    func install(_ provider: AgentProvider) throws
    func remove(_ provider: AgentProvider) throws
    func paneTeamPointerStatus(
        for provider: AgentProvider
    ) throws -> AgentIntegrationStatus
    func installPaneTeamPointer(_ provider: AgentProvider) throws
    func removePaneTeamPointer(_ provider: AgentProvider) throws
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
    /// Whether the "teach agents about pane teams" toggle reads as on.
    /// Derived from the pane-team pointer's on-disk status for whichever
    /// supported providers currently have their hook installed, rather
    /// than a separate persisted preference — the same source-of-truth
    /// approach the per-provider rows already use. Defaults to true when
    /// no supported provider is installed yet, so a fresh install starts
    /// with the toggle on.
    @Published private(set) var paneTeamPointerEnabled = true

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
        refreshPaneTeamPointerEnabled()
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
        // The pointer's own content can go stale the same way the hook
        // helper does (e.g. the app updated and reworded the guide), so
        // repair it alongside the hooks rather than leaving an outdated
        // pointer until the user happens to retoggle it.
        guard paneTeamPointerEnabled else { return }
        for provider in AgentIntegrationInstaller.paneTeamPointerProviders
        where (try? installer.paneTeamPointerStatus(for: provider))
            == .needsRepair {
            try? installer.installPaneTeamPointer(provider)
        }
        refreshPaneTeamPointerEnabled()
    }

    func setInstalled(_ installed: Bool, for provider: AgentProvider) {
        do {
            if installed {
                try installer.install(provider)
                if paneTeamPointerEnabled,
                   AgentIntegrationInstaller.paneTeamPointerProviders
                       .contains(provider) {
                    try? installer.installPaneTeamPointer(provider)
                }
            } else {
                try installer.remove(provider)
                if AgentIntegrationInstaller.paneTeamPointerProviders
                    .contains(provider) {
                    try? installer.removePaneTeamPointer(provider)
                }
            }
            refresh(provider)
        } catch {
            setError(text(for: error), for: provider)
        }
        refreshPaneTeamPointerEnabled()
    }

    func repair(_ provider: AgentProvider) {
        setInstalled(true, for: provider)
    }

    /// Turns the pane-team pointer on or off for every supported provider
    /// that currently has its hook installed. Providers not yet installed
    /// aren't touched here — `setInstalled` picks up the current
    /// preference automatically once they are.
    func setPaneTeamPointerEnabled(_ enabled: Bool) {
        for provider in AgentIntegrationInstaller.paneTeamPointerProviders
        where state(for: provider).status != .notInstalled {
            do {
                if enabled {
                    try installer.installPaneTeamPointer(provider)
                } else {
                    try installer.removePaneTeamPointer(provider)
                }
            } catch {
                setError(text(for: error), for: provider)
            }
        }
        refreshPaneTeamPointerEnabled()
    }

    private func refreshPaneTeamPointerEnabled() {
        let installedCandidates = AgentIntegrationInstaller
            .paneTeamPointerProviders
            .filter { state(for: $0).status != .notInstalled }
        guard !installedCandidates.isEmpty else {
            paneTeamPointerEnabled = true
            return
        }
        paneTeamPointerEnabled = installedCandidates.allSatisfy {
            (try? installer.paneTeamPointerStatus(for: $0)) == .installed
        }
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
