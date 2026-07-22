import CryptoKit
import Foundation
import MyTTYRemoteKit
import os

let remoteAccessLog = Logger(
    subsystem: "dev.mytty.remote-access",
    category: "server"
)

@MainActor
protocol RemoteAccessServerDelegate: AnyObject {
    func remoteAccessServerSnapshot(
        _ server: RemoteAccessServer
    ) -> RemoteSessionSnapshot

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        contentForPaneID paneID: String
    ) -> RemotePaneContent?

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        sendText text: String,
        pressEnter: Bool,
        toPaneID paneID: String
    )

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        pressKey key: String,
        modifiers: [String],
        toPaneID paneID: String
    )

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        scrollBy deltaY: Double,
        inPaneID paneID: String
    )

    func remoteAccessServer(
        _ server: RemoteAccessServer,
        createTabInWindowID windowID: String
    )

    /// The pane's currently scheduled inputs, sorted like the Mac's own
    /// list. Empty (never nil) for an unknown pane.
    func remoteAccessServer(
        _ server: RemoteAccessServer,
        schedulesForPaneID paneID: String
    ) -> [RemotePaneSchedule]

    /// Saves a client-generated schedule. Silently ignored (the delegate
    /// itself is responsible for the no-op) when the pane is unknown or
    /// `schedule.fireAt` is already in the past.
    func remoteAccessServer(
        _ server: RemoteAccessServer,
        createSchedule schedule: RemotePaneSchedule,
        forPaneID paneID: String
    )

    /// Deletes a schedule if it currently belongs to this pane.
    func remoteAccessServer(
        _ server: RemoteAccessServer,
        deleteScheduleID scheduleID: String,
        forPaneID paneID: String
    )
}

enum RemoteAccessServerError: Error {
    case listenerFailed(String)
}

private struct RemoteConnectionState {
    var frameReader = RemoteFrameReader()
    var didHandleFirstFrame = false
    var sessionKey: SymmetricKey?
    var authenticatedDeviceID: String?
    var watchTracker = RemotePaneWatchTracker()
}

@MainActor
final class RemoteAccessServer {
    /// The port the production server prefers, so manual entry (e.g. over
    /// Tailscale) has a stable target across Mac relaunches; the listener
    /// falls back to an ephemeral port when it is taken. Tests leave
    /// `preferredPort` nil so parallel suites never contend for it.
    static let defaultPort: UInt16 = 51820

    static let pollInterval: TimeInterval = 0.15
    /// Delay before the extra poll fired right after delivering remote
    /// input: long enough for the pty echo to land in the terminal
    /// screen, short enough to feel immediate on the phone.
    static let echoPollDelay: TimeInterval = 0.04

    weak var delegate: RemoteAccessServerDelegate?
    let pairingCoordinator: RemotePairingCoordinator
    /// Fires after a new device finishes pairing in the background, so
    /// Settings UI observing `pairedDevices()` can refresh without the
    /// user having to navigate away and back.
    var onDeviceListChanged: (() -> Void)?
    /// Fires whenever the number of authenticated (post-hello) sessions
    /// changes, so UI like the tab sidebar's connection indicator can stay
    /// in sync without polling.
    var onConnectedDeviceCountChanged: ((Int) -> Void)?

    private let deviceStore: RemotePairedDeviceStore
    private let deviceDisplayName: String
    var preferredPort: UInt16?
    private let transport = RemoteAccessTransport()
    private var connectionStates: [RemoteAccessTransport.ConnectionID: RemoteConnectionState] = [:]
    private var pollTimer: Timer?
    private let onError: (Error) -> Void
    private var isRunning = false
    private var lastConnectedDeviceCount = 0
    private var isEchoPollScheduled = false

    var connectedDeviceCount: Int {
        connectionStates.values.filter { $0.authenticatedDeviceID != nil }.count
    }

    var listeningPort: UInt16? { transport.listeningPort }
    /// True as soon as `start()` has been called, even before the
    /// listener actually becomes ready. Unlike `listeningPort`, this is
    /// safe to use as a "should I (re)start?" guard: `listeningPort`
    /// briefly reads `nil` right after `start()`, and using it for that
    /// guard could otherwise tear down and recreate the listener before
    /// it ever finishes coming up.
    var isActive: Bool { isRunning }

    init(
        deviceStore: RemotePairedDeviceStore,
        deviceDisplayName: String,
        onError: @escaping (Error) -> Void
    ) {
        self.deviceStore = deviceStore
        self.deviceDisplayName = deviceDisplayName
        self.pairingCoordinator = RemotePairingCoordinator(deviceStore: deviceStore)
        self.onError = onError
    }

    func start() throws {
        transport.onAccept = { [weak self] id in
            Task { @MainActor [weak self] in self?.handleAccept(id) }
        }
        transport.onData = { [weak self] id, data in
            Task { @MainActor [weak self] in self?.handleData(id, data) }
        }
        transport.onClose = { [weak self] id in
            Task { @MainActor [weak self] in self?.handleClose(id) }
        }
        transport.onListenerError = { [weak self] error in
            Task { @MainActor [weak self] in self?.onError(error) }
        }
        do {
            try transport.start(
                serviceName: deviceDisplayName,
                preferredPort: preferredPort
            )
        } catch {
            throw RemoteAccessServerError.listenerFailed("\(error)")
        }
        isRunning = true
        startPolling()
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        transport.stop()
        connectionStates.removeAll()
        notifyConnectedDeviceCountIfChanged()
    }

    private func notifyConnectedDeviceCountIfChanged() {
        let count = connectedDeviceCount
        guard count != lastConnectedDeviceCount else { return }
        lastConnectedDeviceCount = count
        onConnectedDeviceCountChanged?(count)
    }

    func pairedDevices() -> [RemotePairedDevice] {
        (try? deviceStore.load()) ?? []
    }

    @discardableResult
    func unpair(deviceID: String) -> Bool {
        guard (try? deviceStore.remove(id: deviceID)) != nil else {
            return false
        }
        for (id, state) in connectionStates
            where state.authenticatedDeviceID == deviceID {
            transport.cancel(id)
            connectionStates.removeValue(forKey: id)
        }
        notifyConnectedDeviceCountIfChanged()
        return true
    }

    @discardableResult
    func renamePairedDevice(deviceID: String, name: String) -> Bool {
        guard (try? deviceStore.rename(id: deviceID, name: name)) != nil else {
            return false
        }
        onDeviceListChanged?()
        return true
    }

    func broadcastSnapshot() {
        guard let delegate else { return }
        let snapshot = delegate.remoteAccessServerSnapshot(self)
        for (id, state) in connectionStates
            where state.authenticatedDeviceID != nil {
            send(.snapshot(snapshot), to: id, key: state.sessionKey)
        }
    }

    private func handleAccept(_ id: RemoteAccessTransport.ConnectionID) {
        connectionStates[id] = RemoteConnectionState()
    }

    private func handleClose(_ id: RemoteAccessTransport.ConnectionID) {
        connectionStates.removeValue(forKey: id)
        notifyConnectedDeviceCountIfChanged()
    }

    private func handleData(
        _ id: RemoteAccessTransport.ConnectionID,
        _ data: Data
    ) {
        guard var state = connectionStates[id] else { return }
        let frames: [Data]
        do {
            frames = try state.frameReader.append(data)
        } catch {
            connectionStates.removeValue(forKey: id)
            transport.cancel(id)
            return
        }
        connectionStates[id] = state

        for frame in frames {
            handleFrame(frame, connectionID: id)
        }
    }

    private func handleFrame(
        _ payload: Data,
        connectionID id: RemoteAccessTransport.ConnectionID
    ) {
        guard var state = connectionStates[id] else { return }

        if !state.didHandleFirstFrame {
            state.didHandleFirstFrame = true
            connectionStates[id] = state
            handleHandshake(payload, connectionID: id)
            return
        }

        guard let sessionKey = state.sessionKey,
              let opened = try? RemoteSecureChannel.open(
                  payload,
                  using: sessionKey
              ),
              let message = try? RemoteMessageCodec.decode(opened)
        else {
            connectionStates.removeValue(forKey: id)
            transport.cancel(id)
            return
        }
        handleAuthenticated(message, connectionID: id)
    }

    private func handleHandshake(
        _ payload: Data,
        connectionID id: RemoteAccessTransport.ConnectionID
    ) {
        let pairingKey = pairingCoordinator.activeCode.flatMap {
            code -> SymmetricKey? in
            code.isExpired() ? nil : RemotePairing.derivePresharedKey(
                code: code.value
            )
        }
        guard let (message, key) = RemoteHandshakeResolver.resolve(
            firstFramePayload: payload,
            pairingPresharedKey: pairingKey,
            pairedDevices: pairedDevices()
        ) else {
            connectionStates.removeValue(forKey: id)
            transport.cancel(id)
            return
        }

        switch message {
        case let .pairRequest(deviceName, code):
            guard let result = try? pairingCoordinator.attempt(
                code: code,
                deviceName: deviceName
            ), case let .approved(device) = result else {
                connectionStates.removeValue(forKey: id)
                transport.cancel(id)
                return
            }
            connectionStates.removeValue(forKey: id)
            let transport = self.transport
            // Cancelling right after queuing a send can abort the
            // connection before the bytes actually reach the socket, so
            // the client never sees the approval. Only cancel once the
            // send has actually completed.
            send(
                .pairApproved(
                    deviceID: device.id,
                    deviceSecretBase64: device.secretBase64
                ),
                to: id,
                key: key
            ) {
                transport.cancel(id)
            }
            onDeviceListChanged?()

        case let .hello(deviceID, _):
            guard var state = connectionStates[id] else { return }
            state.sessionKey = key
            state.authenticatedDeviceID = deviceID
            connectionStates[id] = state
            if let delegate {
                let snapshot = delegate.remoteAccessServerSnapshot(self)
                let paneCount = snapshot.windows.reduce(0) {
                    $0 + $1.tabs.reduce(0) { $0 + $1.panes.count }
                }
                remoteAccessLog.notice(
                    "hello from \(deviceID, privacy: .public): sending snapshot with \(snapshot.windows.count, privacy: .public) window(s), \(paneCount, privacy: .public) pane(s)"
                )
                send(.snapshot(snapshot), to: id, key: key)
            }
            notifyConnectedDeviceCountIfChanged()

        default:
            connectionStates.removeValue(forKey: id)
            transport.cancel(id)
        }
    }

    private func handleAuthenticated(
        _ message: RemoteMessage,
        connectionID id: RemoteAccessTransport.ConnectionID
    ) {
        guard var state = connectionStates[id],
              let key = state.sessionKey else { return }

        switch message {
        case let .watchPane(paneID):
            state.watchTracker.watch(paneID: paneID)
            connectionStates[id] = state
            let content = delegate?.remoteAccessServer(
                self,
                contentForPaneID: paneID
            )
            remoteAccessLog.notice(
                "watchPane \(paneID, privacy: .public): delegate returned \(content == nil ? "nil" : "\(content!.text.count) chars", privacy: .public)"
            )
            if let content {
                send(
                    .paneContent(
                        paneID: paneID,
                        text: content.text,
                        cursorRow: content.cursorRow,
                        cursorColumn: content.cursorColumn,
                        styledLines: content.styledLines.isEmpty
                            ? nil
                            : content.styledLines,
                        altScreen: content.altScreen
                    ),
                    to: id,
                    key: key
                )
            }

        case let .unwatchPane(paneID):
            state.watchTracker.unwatch(paneID: paneID)
            connectionStates[id] = state

        case let .sendInput(paneID, text, pressEnter):
            delegate?.remoteAccessServer(
                self,
                sendText: text,
                pressEnter: pressEnter,
                toPaneID: paneID
            )
            scheduleEchoPoll()

        case let .scrollPane(paneID, deltaY):
            delegate?.remoteAccessServer(
                self,
                scrollBy: deltaY,
                inPaneID: paneID
            )
            scheduleEchoPoll()

        case let .sendKey(paneID, key, modifiers):
            delegate?.remoteAccessServer(
                self,
                pressKey: key,
                modifiers: modifiers,
                toPaneID: paneID
            )
            scheduleEchoPoll()

        case let .newTab(windowID):
            delegate?.remoteAccessServer(
                self,
                createTabInWindowID: windowID
            )

        case let .registerPushRelay(pushID, relaySecretBase64):
            registerPushRelay(
                pushID,
                relaySecretBase64: relaySecretBase64,
                connectionID: id
            )

        case let .listPaneSchedules(paneID):
            let schedules = delegate?.remoteAccessServer(
                self,
                schedulesForPaneID: paneID
            ) ?? []
            send(
                .paneSchedules(paneID: paneID, schedules: schedules),
                to: id,
                key: key
            )

        case let .createPaneSchedule(paneID, schedule):
            delegate?.remoteAccessServer(
                self,
                createSchedule: schedule,
                forPaneID: paneID
            )
            let schedules = delegate?.remoteAccessServer(
                self,
                schedulesForPaneID: paneID
            ) ?? []
            send(
                .paneSchedules(paneID: paneID, schedules: schedules),
                to: id,
                key: key
            )

        case let .deletePaneSchedule(paneID, scheduleID):
            delegate?.remoteAccessServer(
                self,
                deleteScheduleID: scheduleID,
                forPaneID: paneID
            )
            let schedules = delegate?.remoteAccessServer(
                self,
                schedulesForPaneID: paneID
            ) ?? []
            send(
                .paneSchedules(paneID: paneID, schedules: schedules),
                to: id,
                key: key
            )

        default:
            break
        }
    }

    /// Stores a relay registration against the device that owns this
    /// authenticated connection. The device ID is taken from the session
    /// rather than the payload so a paired device can only ever register
    /// itself. An empty push ID means "stop pushing to me" (the user
    /// turned notifications off in iOS Settings).
    private func registerPushRelay(
        _ pushID: String,
        relaySecretBase64: String,
        connectionID id: RemoteAccessTransport.ConnectionID
    ) {
        guard let deviceID = connectionStates[id]?.authenticatedDeviceID
        else { return }
        guard !pushID.isEmpty else {
            try? deviceStore.updatePushRegistration(
                id: deviceID,
                pushRelayID: nil,
                relaySecretBase64: nil
            )
            onDeviceListChanged?()
            return
        }
        guard RemotePushRegistrationValidation.isValid(
            pushID: pushID,
            relaySecretBase64: relaySecretBase64
        ) else {
            remoteAccessLog.notice(
                "rejecting malformed push registration from \(deviceID, privacy: .public)"
            )
            return
        }
        do {
            try deviceStore.updatePushRegistration(
                id: deviceID,
                pushRelayID: pushID,
                relaySecretBase64: relaySecretBase64
            )
            onDeviceListChanged?()
        } catch {
            onError(error)
        }
    }

    private func send(
        _ message: RemoteMessage,
        to id: RemoteAccessTransport.ConnectionID,
        key: SymmetricKey?,
        completion: (@Sendable () -> Void)? = nil
    ) {
        guard let key,
              let payload = try? RemoteMessageCodec.encode(message),
              let sealed = try? RemoteSecureChannel.seal(payload, using: key)
        else { return }
        transport.send(
            RemoteFrameCodec.encode(sealed),
            to: id,
            completion: completion
        )
    }

    /// Fires one near-immediate poll after remote input so the keystroke
    /// echo reaches the phone without waiting for the periodic tick.
    /// Coalesced: rapid typing schedules at most one pending poll.
    private func scheduleEchoPoll() {
        guard !isEchoPollScheduled else { return }
        isEchoPollScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.echoPollDelay * 1_000_000_000)
            )
            guard let self else { return }
            self.isEchoPollScheduled = false
            self.pollWatchedPanes()
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(
            timeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.pollWatchedPanes() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollWatchedPanes() {
        guard let delegate else { return }
        for (id, state) in connectionStates {
            guard let key = state.sessionKey else { continue }
            var state = state
            for paneID in state.watchTracker.watchedPaneIDs {
                guard let content = delegate.remoteAccessServer(
                    self,
                    contentForPaneID: paneID
                ) else { continue }
                if let toSend = state.watchTracker.contentToSend(
                    paneID: paneID,
                    current: content
                ) {
                    send(
                        .paneContent(
                            paneID: paneID,
                            text: toSend.text,
                            cursorRow: toSend.cursorRow,
                            cursorColumn: toSend.cursorColumn,
                            styledLines: toSend.styledLines.isEmpty
                                ? nil
                                : toSend.styledLines,
                            altScreen: toSend.altScreen
                        ),
                        to: id,
                        key: key
                    )
                }
            }
            connectionStates[id] = state
        }
    }
}
