import Foundation
import MyTTYCore
import MyTTYRemoteKit

/// Owns the `ControlServer` and its `ControlServerDelegate` conformance:
/// resolving pane IDs across every open window and forwarding
/// `mytty-ctl` requests to the right `TerminalWindowController`. Mirrors
/// `RemoteAccessCoordinator`'s relationship to `RemoteAccessServer`, for
/// the same reason — pane lookups need every live window, which
/// `WindowSessionCoordinator` already tracks.
@MainActor
final class ControlCoordinator {
    let server: ControlServer
    private let windowSessionCoordinator: WindowSessionCoordinator
    private let attentionCenter: AttentionCenter
    private let controlEventLedger: ControlEventLedger
    private let localizerProvider: () -> MyTTYLocalizer
    private let agentJobCoordinator: AgentJobCoordinator
    private let agentIntegrationStatus: (
        AgentProvider
    ) -> AgentIntegrationStatus
    private let integrationStates: () -> [AgentIntegrationSettingsState]
    private let confirmIntegrationInstall: (
        _ providers: [AgentProvider],
        _ isRepair: Bool
    ) -> Bool
    private let installIntegration: (AgentProvider) -> Void

    init(
        socketURL: URL,
        windowSessionCoordinator: WindowSessionCoordinator,
        attentionCenter: AttentionCenter,
        /// Read-only from here: `AppDelegate.receiveAgentEvent` is the only
        /// writer, via `AgentEventServer`'s `onEvent` callback, not this
        /// coordinator.
        controlEventLedger: ControlEventLedger,
        localizerProvider: @escaping () -> MyTTYLocalizer,
        /// Injected rather than read from `AgentIntegrationSettingsModel`
        /// directly, so `agent spawn`'s preflight can be tested with a
        /// stub instead of constructing that model's whole dependency
        /// chain. `AppDelegate` supplies the real
        /// `AgentIntegrationSettingsModel.state(for:).status`.
        agentIntegrationStatus: @escaping (
            AgentProvider
        ) -> AgentIntegrationStatus,
        /// Fresh per-provider integration state for the `integration`
        /// commands; `AppDelegate` refreshes the settings model from disk
        /// before returning its states.
        integrationStates: @escaping () -> [AgentIntegrationSettingsState],
        /// Puts the install/repair confirmation dialog in front of a human
        /// and reports their answer. Lives app-side (not here) so it can
        /// activate the app and run a modal — and so no code path exists
        /// that installs hooks without it.
        confirmIntegrationInstall: @escaping (
            _ providers: [AgentProvider],
            _ isRepair: Bool
        ) -> Bool,
        /// Performs one provider's install after approval — the same
        /// `AgentIntegrationSettingsModel.setInstalled` the Settings
        /// toggle uses, pane-team pointer handling included.
        installIntegration: @escaping (AgentProvider) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.windowSessionCoordinator = windowSessionCoordinator
        self.attentionCenter = attentionCenter
        self.controlEventLedger = controlEventLedger
        self.localizerProvider = localizerProvider
        self.agentIntegrationStatus = agentIntegrationStatus
        self.integrationStates = integrationStates
        self.confirmIntegrationInstall = confirmIntegrationInstall
        self.installIntegration = installIntegration
        agentJobCoordinator = AgentJobCoordinator(
            windowSessionCoordinator: windowSessionCoordinator,
            attentionCenter: attentionCenter,
            integrationStatus: agentIntegrationStatus
        )
        server = ControlServer(socketURL: socketURL, onError: onError)
        server.delegate = self
        server.agentDelegate = agentJobCoordinator
    }

    func start() throws {
        try server.start()
    }

    func stop() {
        server.stop()
    }

    private func terminalSurfaceID(from paneID: String) -> TerminalSurfaceID? {
        guard let uuid = UUID(uuidString: paneID) else { return nil }
        return TerminalSurfaceID(rawValue: uuid)
    }

    private func controller(
        owning paneID: TerminalSurfaceID
    ) -> TerminalWindowController? {
        windowSessionCoordinator.controller(owning: paneID)
    }
}

extension ControlCoordinator: ControlServerDelegate {
    func controlServerListPanes(_ server: ControlServer) -> [ControlPaneInfo] {
        let localizer = localizerProvider()
        let controllers = windowSessionCoordinator.controllers
        let snapshots = controllers.map { $0.paneListSnapshot() }
        let items = PaneListPresentation.items(
            snapshots: snapshots,
            terminalTitle: localizer[.terminal],
            browserTitle: localizer[.browser],
            remoteTitle: localizer[.remotePaneBadge],
            localizer: localizer
        )
        // Remote panes are deliberately absent: mytty-ctl addresses local
        // panes, and a pane ID here has to be one this Mac can split,
        // close, or deliver input to. A pane mirroring another Mac's
        // terminal is none of those, and listing it would hand an
        // orchestrating agent IDs that every other command rejects.
        return items.filter { $0.kind != .remote }.map { item in
            let controller = controllers.first {
                $0.session.id == item.windowID
            }
            let workingDirectory = controller?
                .workingDirectory(forPane: item.paneID)
            let run = attentionCenter.mostRelevantRun(for: item.paneID)
            return ControlPaneInfo(
                paneID: item.paneID.rawValue.uuidString,
                windowID: item.windowID.rawValue.uuidString,
                tabID: item.tabID.rawValue.uuidString,
                title: item.tabTitle,
                command: item.command,
                workingDirectory: workingDirectory?.path,
                isActive: item.isActive,
                provider: run?.provider.rawValue,
                agentState: run?.state.rawValue,
                statusNote: attentionCenter.statusNote(for: item.paneID)
            )
        }
    }

    func controlServer(
        _ server: ControlServer,
        newTabWithWorkingDirectory workingDirectory: String?,
        command: String?
    ) -> String? {
        guard let controller = windowSessionCoordinator.activeController
            ?? windowSessionCoordinator.controllers.first
        else { return nil }
        let url = workingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return controller.newTab(
            workingDirectory: url,
            initialInput: command.map { AgentLaunchPlan.initialInput(command: $0) },
            orchestrated: true
        )?.rawValue.uuidString
    }

    func controlServer(
        _ server: ControlServer,
        splitPaneID paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?,
        command: String?
    ) -> String? {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let controller = controller(owning: surfaceID)
        else { return nil }
        let url = workingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return controller.splitPane(
            surfaceID,
            direction: SplitDirection(rawValue: direction.rawValue)
                ?? .right,
            workingDirectory: url,
            initialInput: command.map { AgentLaunchPlan.initialInput(command: $0) },
            orchestrated: true
        )?.rawValue.uuidString
    }

    func controlServer(
        _ server: ControlServer,
        sendText text: String,
        pressEnter: Bool,
        toPaneID paneID: String
    ) -> Bool {
        guard let surfaceID = terminalSurfaceID(from: paneID) else {
            return false
        }
        return controller(owning: surfaceID)?.deliverRemoteInput(
            paneID: surfaceID,
            text: text,
            pressEnter: pressEnter
        ) ?? false
    }

    func controlServer(
        _ server: ControlServer,
        pressKey key: String,
        modifiers: [String],
        toPaneID paneID: String
    ) -> Bool {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let event = RemoteKeyMapping.event(
                  key: key,
                  modifiers: modifiers
              )
        else { return false }
        return controller(owning: surfaceID)?.deliverRemoteKey(
            paneID: surfaceID,
            event: event
        ) ?? false
    }

    func controlServer(
        _ server: ControlServer,
        contentForPaneID paneID: String
    ) -> ControlPaneContent? {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let controller = controller(owning: surfaceID),
              let content = controller.remotePaneContent(forPane: surfaceID)
        else { return nil }
        return ControlPaneContent(
            paneID: paneID,
            text: content.text,
            cursorRow: content.cursorRow,
            cursorColumn: content.cursorColumn
        )
    }

    func controlServer(
        _ server: ControlServer,
        agentStateForPaneID paneID: String
    ) -> AgentRunState?? {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              controller(owning: surfaceID) != nil
        else { return nil }
        return .some(attentionCenter.mostRelevantRun(for: surfaceID)?.state)
    }

    func controlServer(
        _ server: ControlServer,
        setStatusNote note: String?,
        forPaneID paneID: String
    ) -> String? {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              controller(owning: surfaceID) != nil
        else { return "pane-not-found" }
        guard let note else {
            attentionCenter.clearStatusNote(for: surfaceID)
            return nil
        }
        guard ControlStatusNoteValidation.isValid(note) else {
            return "invalid-status"
        }
        attentionCenter.setStatusNote(note, for: surfaceID)
        return nil
    }

    func controlServer(
        _ server: ControlServer,
        waitPreflightFailureCodeForPaneID paneID: String,
        until condition: ControlWaitCondition
    ) -> String? {
        // An unresolvable pane is left to the poll loop's own
        // pane-not-found answer; an unrecognized foreground process
        // (plain shell, unknown binary, or an agent launched so recently
        // the 0.5s process poll hasn't seen it yet) stays waitable.
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let provider = controller(owning: surfaceID)?
                  .foregroundAgentProvider(forPane: surfaceID)
        else { return nil }
        return AgentIntegrationPreflight.waitFailureCode(
            for: agentIntegrationStatus(provider),
            until: condition
        )
    }

    func controlServer(
        _ server: ControlServer,
        eventsAfterSequence sequence: UInt64
    ) -> (records: [ControlAgentEventRecord], latestSequence: UInt64) {
        (
            records: controlEventLedger.records(after: sequence),
            latestSequence: controlEventLedger.latestSequence
        )
    }

    func controlServer(
        _ server: ControlServer,
        closePaneID paneID: String
    ) -> Bool {
        guard let surfaceID = terminalSurfaceID(from: paneID) else {
            return false
        }
        return controller(owning: surfaceID)?
            .closePane(forControl: surfaceID) ?? false
    }

    func controlServer(
        _ server: ControlServer,
        focusPaneID paneID: String
    ) -> Bool {
        guard let surfaceID = terminalSurfaceID(from: paneID) else {
            return false
        }
        return controller(owning: surfaceID)?.focus(pane: surfaceID) ?? false
    }

    func controlServerIntegrationStatuses(
        _ server: ControlServer
    ) -> [ControlIntegrationInfo] {
        integrationStates().map { state in
            ControlIntegrationInfo(
                provider: state.provider.rawValue,
                status: state.status.controlValue,
                error: state.errorMessage
            )
        }
    }

    func controlServer(
        _ server: ControlServer,
        enableIntegrationFor provider: AgentProvider
    ) -> Result<[ControlIntegrationInfo], AgentControlFailure> {
        installIntegrations(
            targets: currentStatus(of: provider) == .installed
                ? []
                : [provider],
            isRepair: false
        )
    }

    func controlServer(
        _ server: ControlServer,
        repairIntegrationsFor provider: AgentProvider?
    ) -> Result<[ControlIntegrationInfo], AgentControlFailure> {
        // An explicitly named provider is always repaired (repairing a
        // not-yet-installed one is just an install); the no-argument form
        // only touches integrations that report needs-repair.
        let targets = provider.map { [$0] }
            ?? integrationStates()
                .filter { $0.status == .needsRepair }
                .map(\.provider)
        return installIntegrations(targets: targets, isRepair: true)
    }

    /// Shared enable/repair path: an empty `targets` is already satisfied
    /// and returns fresh statuses without bothering a human; otherwise the
    /// confirmation dialog decides between installing and
    /// `integration-declined`.
    private func installIntegrations(
        targets: [AgentProvider],
        isRepair: Bool
    ) -> Result<[ControlIntegrationInfo], AgentControlFailure> {
        guard !targets.isEmpty else {
            return .success(controlServerIntegrationStatuses(server))
        }
        guard confirmIntegrationInstall(targets, isRepair) else {
            return .failure(AgentControlFailure("integration-declined"))
        }
        targets.forEach(installIntegration)
        return .success(controlServerIntegrationStatuses(server))
    }

    private func currentStatus(
        of provider: AgentProvider
    ) -> AgentIntegrationStatus {
        integrationStates()
            .first { $0.provider == provider }?
            .status ?? .notInstalled
    }
}
