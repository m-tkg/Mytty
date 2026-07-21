import Combine
import Foundation
import MyTTYCore

@MainActor
protocol AgentIntegrationInstalling {
    func status(for provider: AgentProvider) throws -> AgentIntegrationStatus
    func install(_ provider: AgentProvider) throws
    func remove(_ provider: AgentProvider) throws
    func paneTeamPointerStatus(
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) throws -> AgentIntegrationStatus
    func installPaneTeamPointer(
        _ provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) throws
    func removePaneTeamPointer(_ provider: AgentProvider) throws
    /// Where a provider's pane-team pointer lives on disk, or `nil` if the
    /// provider has none. Display-only; never used to decide whether to
    /// write anything.
    func paneTeamPointerURL(for provider: AgentProvider) -> URL?
    /// The exact text `installPaneTeamPointer` would write for `provider`,
    /// without writing it. Backs the Orchestration settings "preview"
    /// disclosure -- must stay identical to the real write, so it's
    /// sourced from the same private helpers as `installPaneTeamPointer`
    /// rather than duplicated in the UI layer.
    func paneTeamPointerPreview(
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) -> String?
    /// Where the guide Markdown file lives -- the file every pane-team
    /// pointer now just refers to, rather than embedding the recipe
    /// itself. Display-only, same reasoning as `paneTeamPointerURL`.
    var installedGuideMarkdown: URL { get }
}

extension AgentIntegrationInstaller: AgentIntegrationInstalling {}

/// Where the persisted "teach agents about Mytty orchestration" preference lives.
/// A thin seam over `ApplicationPreferences.paneTeamPointersEnabled` so
/// `AgentIntegrationSettingsModel` doesn't have to know about
/// `ApplicationPreferencesStore` or the settings file's URL directly, and
/// tests can substitute an in-memory fake instead of touching disk.
@MainActor
protocol PaneTeamPointerPreferenceStoring {
    var paneTeamPointersEnabled: Bool { get set }
}

/// Production-backing for `PaneTeamPointerPreferenceStoring`: reads and
/// writes the shared application preferences file directly, independent of
/// whatever `SettingsModel` instance the Settings window happens to be
/// showing. Both re-read the file on every access, so the two stay
/// consistent without needing to share an object.
struct ApplicationPreferencesPaneTeamPointerStore:
    PaneTeamPointerPreferenceStoring {
    let store: ApplicationPreferencesStore
    let configurationURL: URL

    var paneTeamPointersEnabled: Bool {
        get {
            (try? store.load(from: configurationURL))?
                .paneTeamPointersEnabled ?? true
        }
        nonmutating set {
            guard var preferences = try? store.load(from: configurationURL)
            else { return }
            preferences.paneTeamPointersEnabled = newValue
            try? store.save(preferences, to: configurationURL)
        }
    }
}

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
    /// Whether the "teach agents about Mytty orchestration" toggle reads as on.
    /// Backed by the persisted `paneTeamPointersEnabled` preference (see
    /// `PaneTeamPointerPreferenceStoring`), not derived from on-disk
    /// pointer status — a provider whose hook is already installed but
    /// whose pointer hasn't been written yet (e.g. an existing user after
    /// an app update) must still show the toggle on, and `refresh` /
    /// `repairInstalledIntegrations` are what backfill the pointer to
    /// match.
    @Published private(set) var paneTeamPointerEnabled: Bool

    private let installer: any AgentIntegrationInstalling
    private var preferenceStore: any PaneTeamPointerPreferenceStoring

    init(
        installer: any AgentIntegrationInstalling,
        preferenceStore: any PaneTeamPointerPreferenceStoring
    ) {
        self.installer = installer
        self.preferenceStore = preferenceStore
        paneTeamPointerEnabled = preferenceStore.paneTeamPointersEnabled
        states = Self.providers.map {
            AgentIntegrationSettingsState(
                provider: $0,
                status: .notInstalled,
                errorMessage: nil
            )
        }
        refresh()
    }

    /// Current on-disk status of `provider`'s pane-team pointer (the
    /// generated note in that provider's global config, not the hook
    /// itself). Used by the Orchestration settings section to show
    /// per-file status; re-reads disk on every call, which is fine at the
    /// UI refresh cadence this backs.
    func paneTeamPointerStatus(
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) -> AgentIntegrationStatus {
        (try? installer.paneTeamPointerStatus(for: provider, language: language))
            ?? .notInstalled
    }

    /// Where `provider`'s pane-team pointer lives on disk, or `nil` if the
    /// provider doesn't support one.
    func paneTeamPointerURL(for provider: AgentProvider) -> URL? {
        installer.paneTeamPointerURL(for: provider)
    }

    /// The exact text that would be written for `provider`'s pane-team
    /// pointer, without writing it. Sourced from the installer so the
    /// preview can never drift from the real write.
    func paneTeamPointerPreview(
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) -> String? {
        installer.paneTeamPointerPreview(for: provider, language: language)
    }

    /// Where the guide Markdown file lives on disk -- the file every
    /// pane-team pointer now just points at.
    var guideMarkdownURL: URL {
        installer.installedGuideMarkdown
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
        paneTeamPointerEnabled = preferenceStore.paneTeamPointersEnabled
    }

    func repairInstalledIntegrations(language: PaneTeamPointerLanguage) {
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
        // helper does (e.g. the app updated and reworded the guide, or the
        // user switched the app's language), so repair it alongside the
        // hooks rather than leaving an outdated pointer until the user
        // happens to retoggle it. This also covers providers whose pointer
        // was simply never written -- notably an existing user's
        // already-installed Codex/Claude Code integration from before this
        // preference existed -- so the pointer reaches them on the next
        // launch instead of requiring a manual retoggle.
        guard paneTeamPointerEnabled else { return }
        for provider in AgentIntegrationInstaller.paneTeamPointerProviders
        where state(for: provider).status != .notInstalled {
            let pointerStatus = try? installer.paneTeamPointerStatus(
                for: provider,
                language: language
            )
            guard pointerStatus == .needsRepair
                || pointerStatus == .notInstalled
            else { continue }
            try? installer.installPaneTeamPointer(provider, language: language)
        }
    }

    func setInstalled(
        _ installed: Bool,
        for provider: AgentProvider,
        language: PaneTeamPointerLanguage
    ) {
        do {
            if installed {
                try installer.install(provider)
                if paneTeamPointerEnabled,
                   AgentIntegrationInstaller.paneTeamPointerProviders
                       .contains(provider) {
                    try? installer.installPaneTeamPointer(
                        provider,
                        language: language
                    )
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
    }

    func repair(_ provider: AgentProvider, language: PaneTeamPointerLanguage) {
        setInstalled(true, for: provider, language: language)
    }

    /// Persists the pane-team pointer preference and applies it to every
    /// supported provider that currently has its hook installed. Providers
    /// not yet installed aren't touched here — `setInstalled` picks up the
    /// persisted preference automatically once they are, and
    /// `repairInstalledIntegrations` backfills any that were installed
    /// while the preference was already on.
    func setPaneTeamPointerEnabled(
        _ enabled: Bool,
        language: PaneTeamPointerLanguage
    ) {
        preferenceStore.paneTeamPointersEnabled = enabled
        paneTeamPointerEnabled = enabled
        for provider in AgentIntegrationInstaller.paneTeamPointerProviders
        where state(for: provider).status != .notInstalled {
            do {
                if enabled {
                    try installer.installPaneTeamPointer(
                        provider,
                        language: language
                    )
                } else {
                    try installer.removePaneTeamPointer(provider)
                }
            } catch {
                setError(text(for: error), for: provider)
            }
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
