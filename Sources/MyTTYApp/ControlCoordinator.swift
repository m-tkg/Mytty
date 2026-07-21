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
    private let localizerProvider: () -> MyTTYLocalizer
    private let agentJobCoordinator: AgentJobCoordinator

    init(
        socketURL: URL,
        windowSessionCoordinator: WindowSessionCoordinator,
        attentionCenter: AttentionCenter,
        localizerProvider: @escaping () -> MyTTYLocalizer,
        /// Injected rather than read from `AgentIntegrationSettingsModel`
        /// directly, so `agent spawn`'s preflight can be tested with a
        /// stub instead of constructing that model's whole dependency
        /// chain. `AppDelegate` supplies the real
        /// `AgentIntegrationSettingsModel.state(for:).status`.
        agentIntegrationStatus: @escaping (
            AgentProvider
        ) -> AgentIntegrationStatus,
        onError: @escaping (Error) -> Void
    ) {
        self.windowSessionCoordinator = windowSessionCoordinator
        self.attentionCenter = attentionCenter
        self.localizerProvider = localizerProvider
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
            localizer: localizer
        )
        return items.map { item in
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
                agentState: run?.state.rawValue
            )
        }
    }

    func controlServer(
        _ server: ControlServer,
        newTabWithWorkingDirectory workingDirectory: String?
    ) -> String? {
        guard let controller = windowSessionCoordinator.activeController
            ?? windowSessionCoordinator.controllers.first
        else { return nil }
        let url = workingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return controller.newTab(workingDirectory: url)?
            .rawValue.uuidString
    }

    func controlServer(
        _ server: ControlServer,
        splitPaneID paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?
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
            workingDirectory: url
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
}
