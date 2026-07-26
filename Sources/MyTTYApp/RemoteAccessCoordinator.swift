import Foundation
import MyTTYCore
import MyTTYRemoteKit

/// Owns the `RemoteAccessServer` and its `RemoteAccessServerDelegate`
/// conformance: building the pane/tab snapshot the iOS remote sees,
/// resolving pane IDs, and forwarding remote input/key events and tab
/// creation to the right `TerminalWindowController`. Since all of that
/// requires enumerating live windows, this coordinator holds a reference to
/// `WindowSessionCoordinator` (the owner of the controllers array) rather
/// than duplicating window bookkeeping.
@MainActor
final class RemoteAccessCoordinator {
    let server: RemoteAccessServer
    let settingsModel: RemoteAccessSettingsModel
    private let windowSessionCoordinator: WindowSessionCoordinator
    private let localizerProvider: () -> MyTTYLocalizer
    /// Read only to fill each pane's agent status in the snapshot; this
    /// coordinator never appends to it. Supplied as a closure because the
    /// `AttentionCenter` is built after this coordinator during launch.
    private let attentionCenterProvider: () -> AttentionCenter?

    init(
        deviceStoreURL: URL,
        deviceDisplayName: String,
        windowSessionCoordinator: WindowSessionCoordinator,
        attentionCenterProvider: @escaping () -> AttentionCenter?,
        localizerProvider: @escaping () -> MyTTYLocalizer
    ) {
        self.windowSessionCoordinator = windowSessionCoordinator
        self.attentionCenterProvider = attentionCenterProvider
        self.localizerProvider = localizerProvider
        let server = RemoteAccessServer(
            deviceStore: RemotePairedDeviceStore(fileURL: deviceStoreURL),
            deviceDisplayName: deviceDisplayName,
            onError: { error in
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "remote access"
                )
            }
        )
        server.preferredPort = RemoteAccessServer.defaultPort
        self.server = server
        self.settingsModel = RemoteAccessSettingsModel(server: server)
        server.delegate = self
        server.onConnectedDeviceCountChanged = { [weak self] count in
            self?.updateConnectionIndicator(count > 0)
        }
    }

    func updateRemoteAccessServer(enabled: Bool) {
        if enabled {
            guard !server.isActive else { return }
            do {
                try server.start()
            } catch {
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "remote access"
                )
            }
        } else {
            server.stop()
        }
        settingsModel.refresh()
    }

    private func updateConnectionIndicator(_ connected: Bool) {
        windowSessionCoordinator.isRemoteAccessConnected = connected
        windowSessionCoordinator.controllers.forEach {
            $0.setRemoteAccessConnected(connected)
        }
    }

    private func terminalSurfaceID(from paneID: String) -> TerminalSurfaceID? {
        guard let uuid = UUID(uuidString: paneID) else { return nil }
        return TerminalSurfaceID(rawValue: uuid)
    }

    /// Built fresh per call rather than stored: `paneInputScheduler` is
    /// assigned onto `windowSessionCoordinator` after this coordinator is
    /// constructed (see `AppDelegate`), so capturing it once at init would
    /// permanently see `nil`.
    private var paneScheduleService: RemotePaneScheduleService {
        RemotePaneScheduleService(
            scheduler: windowSessionCoordinator.paneInputScheduler,
            paneExists: { [weak self] surfaceID in
                guard let self else { return false }
                return self.windowSessionCoordinator.controllers.contains {
                    $0.remotePaneContent(forPane: surfaceID) != nil
                }
            },
            onError: { error in
                WindowSessionCoordinator.reportPersistenceError(
                    error,
                    operation: "remote scheduled input"
                )
            }
        )
    }
}

extension RemoteAccessCoordinator: RemoteAccessServerDelegate {
    func remoteAccessServerSnapshot(
        _ server: RemoteAccessServer
    ) -> RemoteSessionSnapshot {
        let localizer = localizerProvider()
        let snapshots = windowSessionCoordinator.controllers.map {
            $0.paneListSnapshot()
        }
        let items = PaneListPresentation.items(
            snapshots: snapshots,
            terminalTitle: localizer[.terminal],
            browserTitle: localizer[.browser],
            remoteTitle: localizer[.remotePaneBadge],
            localizer: localizer
        )
        let windows: [RemoteWindow] = snapshots.compactMap { snapshot in
            let tabs: [RemoteTab] = snapshot.session.tabs.compactMap { tab in
                let panes: [RemotePane] = items
                    .filter {
                        $0.windowID == snapshot.session.id
                            && $0.tabID == tab.id
                            // A pane already mirroring a third Mac is not
                            // offered onward: this Mac has no surface to
                            // read or deliver input to for it, so a client
                            // would see a pane it could never type into.
                            && $0.kind != .remote
                    }
                    .map { item in
                        RemotePane(
                            id: item.paneID.rawValue.uuidString,
                            title: item.tabTitle,
                            command: item.command,
                            location: item.location,
                            kind: item.kind == .terminal
                                ? .terminal : .browser,
                            isActive: item.isActive,
                            agent: self.agentStatus(for: item)
                        )
                    }
                guard !panes.isEmpty else { return nil }
                return RemoteTab(
                    id: tab.id.rawValue.uuidString,
                    title: panes.first?.title ?? "",
                    panes: panes
                )
            }
            guard !tabs.isEmpty else { return nil }
            return RemoteWindow(
                id: snapshot.session.id.rawValue.uuidString,
                tabs: tabs
            )
        }
        return RemoteSessionSnapshot(
            windows: windows,
            serverProtocolVersion: RemoteMessageCodec.protocolVersion
        )
    }

    /// The host's own view of the agent in a pane, for clients that cannot
    /// see the process or read the transcript themselves. Only terminals
    /// have one: a browser pane runs no agent.
    private func agentStatus(for item: PaneListItem) -> RemotePaneAgentStatus? {
        guard item.kind == .terminal,
              let attentionCenter = attentionCenterProvider()
        else { return nil }
        let run = attentionCenter.mostRelevantRun(for: item.paneID)
        let session = windowSessionCoordinator.controllers
            .compactMap { $0.agentSessionStatus(forPane: item.paneID) }
            .first
        let status = RemotePaneAgentStatus(
            provider: run?.provider.rawValue,
            state: run?.state.rawValue,
            modelName: session?.modelName,
            contextRemainingPercent: session?.contextRemainingPercent,
            needsAttention: attentionCenter.items.contains {
                $0.surfaceID == item.paneID && $0.isActionable
            }
        )
        // Sending an all-nil status would cost a field per pane on every
        // snapshot and tell the client nothing it does not already assume.
        return status.isEmpty ? nil : status
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        contentForPaneID paneID: String
    ) -> RemotePaneContent? {
        guard let surfaceID = terminalSurfaceID(from: paneID) else {
            remoteAccessLog.notice(
                "contentForPaneID \(paneID, privacy: .public): not a valid UUID"
            )
            return nil
        }
        for controller in windowSessionCoordinator.controllers {
            if let content = controller.remotePaneContent(
                forPane: surfaceID
            ) {
                return content
            }
        }
        remoteAccessLog.notice(
            "contentForPaneID \(paneID, privacy: .public): no controller has this surface (checked \(self.windowSessionCoordinator.controllers.count, privacy: .public))"
        )
        return nil
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        sendText text: String,
        pressEnter: Bool,
        paste: Bool,
        toPaneID paneID: String
    ) {
        guard let surfaceID = terminalSurfaceID(from: paneID) else { return }
        for controller in windowSessionCoordinator.controllers
            where controller.deliverRemoteInput(
                paneID: surfaceID,
                text: text,
                pressEnter: pressEnter,
                paste: paste
            ) {
            return
        }
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        pressKey key: String,
        modifiers: [String],
        toPaneID paneID: String
    ) {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let event = RemoteKeyMapping.event(key: key, modifiers: modifiers)
        else {
            remoteAccessLog.notice(
                "pressKey \(key, privacy: .public): no mapping or invalid pane"
            )
            return
        }
        for controller in windowSessionCoordinator.controllers
            where controller.deliverRemoteKey(
                paneID: surfaceID,
                event: event
            ) {
            return
        }
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        scrollBy deltaY: Double,
        inPaneID paneID: String
    ) {
        guard let surfaceID = terminalSurfaceID(from: paneID) else { return }
        for controller in windowSessionCoordinator.controllers
            where controller.deliverRemoteScroll(
                paneID: surfaceID,
                deltaY: deltaY
            ) {
            return
        }
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        createTabInWindowID windowID: String
    ) {
        guard let uuid = UUID(uuidString: windowID) else { return }
        let id = WindowID(rawValue: uuid)
        windowSessionCoordinator.controllers
            .first { $0.session.id == id }?.newTab()
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        schedulesForPaneID paneID: String
    ) -> [RemotePaneSchedule] {
        paneScheduleService.schedules(forPaneID: paneID)
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        createSchedule schedule: RemotePaneSchedule,
        forPaneID paneID: String
    ) {
        paneScheduleService.create(schedule, forPaneID: paneID)
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        deleteScheduleID scheduleID: String,
        forPaneID paneID: String
    ) {
        paneScheduleService.delete(scheduleID: scheduleID, forPaneID: paneID)
    }
}
