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

    init(
        deviceStoreURL: URL,
        deviceDisplayName: String,
        windowSessionCoordinator: WindowSessionCoordinator,
        localizerProvider: @escaping () -> MyTTYLocalizer
    ) {
        self.windowSessionCoordinator = windowSessionCoordinator
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
            localizer: localizer
        )
        let windows: [RemoteWindow] = snapshots.compactMap { snapshot in
            let tabs: [RemoteTab] = snapshot.session.tabs.compactMap { tab in
                let panes: [RemotePane] = items
                    .filter {
                        $0.windowID == snapshot.session.id
                            && $0.tabID == tab.id
                    }
                    .map { item in
                        RemotePane(
                            id: item.paneID.rawValue.uuidString,
                            title: item.tabTitle,
                            command: item.command,
                            location: item.location,
                            kind: item.kind == .terminal
                                ? .terminal : .browser,
                            isActive: item.isActive
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
        toPaneID paneID: String
    ) {
        guard let surfaceID = terminalSurfaceID(from: paneID) else { return }
        for controller in windowSessionCoordinator.controllers
            where controller.deliverRemoteInput(
                paneID: surfaceID,
                text: text,
                pressEnter: pressEnter
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
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let scheduler = windowSessionCoordinator.paneInputScheduler
        else { return [] }
        return scheduler.schedules(for: surfaceID).map {
            RemotePaneSchedule(
                id: $0.id.rawValue.uuidString,
                fireAt: $0.fireAt,
                text: $0.text,
                pressEnter: $0.appendNewline
            )
        }
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        createSchedule schedule: RemotePaneSchedule,
        forPaneID paneID: String
    ) {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let scheduleUUID = UUID(uuidString: schedule.id),
              let scheduler = windowSessionCoordinator.paneInputScheduler,
              windowSessionCoordinator.controllers.contains(where: {
                  $0.remotePaneContent(forPane: surfaceID) != nil
              })
        else { return }
        let paneInputSchedule = PaneInputSchedule(
            id: PaneInputScheduleID(rawValue: scheduleUUID),
            surfaceID: surfaceID,
            fireAt: schedule.fireAt,
            text: schedule.text,
            appendNewline: schedule.pressEnter
        )
        // A past `fireAt` throws `PaneInputSchedulerError.pastDate`; that is
        // silently dropped here, so the reply list just won't contain it.
        try? scheduler.save(paneInputSchedule)
    }

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        deleteScheduleID scheduleID: String,
        forPaneID paneID: String
    ) {
        guard let surfaceID = terminalSurfaceID(from: paneID),
              let scheduleUUID = UUID(uuidString: scheduleID),
              let scheduler = windowSessionCoordinator.paneInputScheduler
        else { return }
        let id = PaneInputScheduleID(rawValue: scheduleUUID)
        guard scheduler.schedules(for: surfaceID).contains(where: {
            $0.id == id
        }) else { return }
        try? scheduler.delete(id: id)
    }
}
