import Combine
import CryptoKit
import Foundation
import Network
import MyTTYRemoteKit

enum RemoteClientError: Error {
    case connectionClosed
    case protocolError
    case noEndpoint
    case cancelled
    case timedOut
}

@MainActor
final class RemoteClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    struct PaneScreen: Equatable {
        var text: String
        var cursorRow: Int?
        var cursorColumn: Int?
        /// Colored lines bottom-aligned to `text`; empty or shorter than
        /// `text` means the top lines render without color.
        var styledLines: [RemoteStyledLine] = []
        /// True when the pane only has a screen-sized buffer (an
        /// alternate-screen TUI): scroll gestures are forwarded to the
        /// Mac instead of scrolling the mirrored text locally.
        var altScreen = false
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var snapshot: RemoteSessionSnapshot?
    @Published private(set) var paneContent: [String: PaneScreen] = [:]
    @Published private(set) var paneSchedules: [String: [RemotePaneSchedule]] = [:]

    var isConnected: Bool { state == .connected }

    /// True once the connected Mac has confirmed it understands the
    /// pane-schedule messages; older servers close the connection on an
    /// unknown message type, so callers must gate on this before sending.
    var supportsPaneSchedules: Bool { serverProtocolVersion >= 4 }

    private var transport: RemoteConnectionTransport?
    private var sessionKey: SymmetricKey?
    /// The Mac connected to most recently, so views deep in the navigation
    /// stack can trigger a reconnect without carrying the `PairedMac`.
    private var lastConnectedMac: PairedMac?
    private var pairingContinuation: CheckedContinuation<PairedMac, Error>?
    private var pairingTimeoutTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    /// Connect/pair attempts to unreachable addresses can otherwise sit in
    /// Network.framework's retrying `.waiting` state forever.
    static let attemptTimeout: Duration = .seconds(30)
    private var pairingEndpointInfo: (macName: String, host: String?, port: UInt16?)?
    private var pairingLabel = ""
    private let pushRegistration: PushRegistration
    private var pushRegistrationObserver: AnyCancellable?
    /// The version reported by the connected Mac, so features added after
    /// version 1 are only used where they will decode. Older servers close
    /// the connection on an unknown message type.
    private var serverProtocolVersion = 1

    init(pushRegistration: PushRegistration = .shared) {
        self.pushRegistration = pushRegistration
        // The token can land after the session is already up (first launch
        // asks for permission), so re-send whenever it changes.
        pushRegistrationObserver = pushRegistration.$registration
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sendPushRegistration()
                }
            }
    }

    // MARK: Pairing

    func pair(
        macName: String?,
        endpoint: NWEndpoint,
        code: String,
        deviceName: String,
        label: String
    ) async throws -> PairedMac {
        disconnect()
        let key = RemotePairing.derivePresharedKey(code: code)
        pairingEndpointInfo = addressingInfo(macName: macName, endpoint: endpoint)
        pairingLabel = label

        let transport = RemoteConnectionTransport(endpoint: endpoint)
        self.transport = transport

        transport.onReady = { [weak self] in
            Task { @MainActor [weak self] in
                self?.sendPairRequest(deviceName: deviceName, code: code, key: key)
            }
        }
        transport.onFrame = { [weak self] frame in
            Task { @MainActor [weak self] in
                self?.handlePairingFrame(frame, key: key)
            }
        }
        transport.onClose = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.failPairing(error ?? RemoteClientError.connectionClosed)
            }
        }

        pairingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.attemptTimeout)
            guard !Task.isCancelled else { return }
            self?.transport?.cancel()
            self?.failPairing(RemoteClientError.timedOut)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.pairingContinuation = continuation
            transport.start()
        }
    }

    /// Abandons an in-flight pairing attempt; the pending `pair` call
    /// throws `RemoteClientError.cancelled`.
    func cancelPairing() {
        failPairing(RemoteClientError.cancelled)
        transport?.cancel()
        transport = nil
    }

    private func sendPairRequest(
        deviceName: String,
        code: String,
        key: SymmetricKey
    ) {
        guard let payload = try? RemoteMessageCodec.encode(
            .pairRequest(deviceName: deviceName, code: code)
        ), let sealed = try? RemoteSecureChannel.seal(payload, using: key)
        else {
            failPairing(RemoteClientError.protocolError)
            return
        }
        transport?.send(RemoteFrameCodec.encode(sealed))
    }

    private func handlePairingFrame(_ frame: Data, key: SymmetricKey) {
        guard let opened = try? RemoteSecureChannel.open(frame, using: key),
              let message = try? RemoteMessageCodec.decode(opened),
              case let .pairApproved(deviceID, deviceSecretBase64) = message
        else {
            failPairing(RemoteClientError.protocolError)
            return
        }
        let info = pairingEndpointInfo
        let mac = PairedMac(
            deviceID: deviceID,
            deviceSecretBase64: deviceSecretBase64,
            macName: info?.macName ?? "",
            manualHost: info?.host,
            manualPort: info?.port,
            displayName: pairingLabel
        )
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        pairingContinuation?.resume(returning: mac)
        pairingContinuation = nil
        transport?.cancel()
        transport = nil
    }

    private func failPairing(_ error: Error) {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        guard let continuation = pairingContinuation else { return }
        pairingContinuation = nil
        transport = nil
        continuation.resume(throwing: error)
    }

    private func addressingInfo(
        macName: String?,
        endpoint: NWEndpoint
    ) -> (macName: String, host: String?, port: UInt16?) {
        if let macName, !macName.isEmpty {
            return (macName, nil, nil)
        }
        if case let .hostPort(host, port) = endpoint {
            return ("", "\(host)", port.rawValue)
        }
        return ("", nil, nil)
    }

    // MARK: Session

    func connect(mac: PairedMac) {
        disconnect()
        lastConnectedMac = mac
        guard let endpoint = mac.reconnectEndpoint() else {
            state = .failed("No address to reconnect to")
            return
        }
        state = .connecting
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.attemptTimeout)
            guard !Task.isCancelled, let self,
                  self.state == .connecting else { return }
            self.transport?.cancel()
            self.transport = nil
            self.state = .failed("Connection timed out")
        }
        let key = SymmetricKey(data: mac.deviceSecret)
        sessionKey = key

        let transport = RemoteConnectionTransport(endpoint: endpoint)
        self.transport = transport

        transport.onReady = { [weak self] in
            Task { @MainActor [weak self] in
                self?.sendHello(deviceID: mac.deviceID, key: key)
            }
        }
        transport.onFrame = { [weak self] frame in
            Task { @MainActor [weak self] in
                self?.handleSessionFrame(frame, key: key)
            }
        }
        transport.onClose = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleSessionClose(error)
            }
        }
        transport.start()
    }

    /// Reconnects to the most recently connected Mac, e.g. from a
    /// disconnected pane view. No-op if there is nothing to reconnect to.
    /// The navigation stack is left alone: views deep in it re-resolve
    /// themselves against the new snapshot and only pop if what they show
    /// is gone.
    func reconnect() {
        guard let mac = lastConnectedMac else { return }
        connect(mac: mac)
    }

    var canReconnect: Bool { lastConnectedMac != nil }

    /// Lets a caller tell whether the session already on screen is the
    /// one it wants, rather than reconnecting and throwing away a live
    /// connection along with the pane content it has already mirrored.
    var connectedMacID: String? { lastConnectedMac?.deviceID }

    func disconnect() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        transport?.cancel()
        transport = nil
        sessionKey = nil
        if state != .disconnected { state = .disconnected }
        snapshot = nil
        paneContent = [:]
        paneSchedules = [:]
    }

    func watchPane(_ paneID: String) {
        send(.watchPane(paneID: paneID))
    }

    func unwatchPane(_ paneID: String) {
        send(.unwatchPane(paneID: paneID))
    }

    func sendInput(paneID: String, text: String, pressEnter: Bool) {
        send(.sendInput(paneID: paneID, text: text, pressEnter: pressEnter))
    }

    func sendKey(paneID: String, key: String, modifiers: [String]) {
        send(.sendKey(paneID: paneID, key: key, modifiers: modifiers))
    }

    /// Forwards a scroll gesture to an alternate-screen pane as
    /// mouse-wheel lines (positive = toward older content).
    func sendScroll(paneID: String, deltaY: Double) {
        send(.scrollPane(paneID: paneID, deltaY: deltaY))
    }

    func newTab(windowID: String) {
        send(.newTab(windowID: windowID))
    }

    func requestPaneSchedules(paneID: String) {
        guard state == .connected, supportsPaneSchedules else { return }
        send(.listPaneSchedules(paneID: paneID))
    }

    func createPaneSchedule(
        paneID: String,
        fireAt: Date,
        text: String,
        pressEnter: Bool
    ) {
        guard state == .connected, supportsPaneSchedules else { return }
        send(
            .createPaneSchedule(
                paneID: paneID,
                schedule: RemotePaneSchedule(
                    id: UUID().uuidString,
                    fireAt: fireAt,
                    text: text,
                    pressEnter: pressEnter
                )
            )
        )
    }

    func deletePaneSchedule(paneID: String, scheduleID: String) {
        guard state == .connected, supportsPaneSchedules else { return }
        send(.deletePaneSchedule(paneID: paneID, scheduleID: scheduleID))
    }

    private func sendHello(deviceID: String, key: SymmetricKey) {
        guard let payload = try? RemoteMessageCodec.encode(
            .hello(
                deviceID: deviceID,
                protocolVersion: RemoteMessageCodec.protocolVersion
            )
        ), let sealed = try? RemoteSecureChannel.seal(payload, using: key)
        else {
            state = .failed("Could not start session")
            return
        }
        transport?.send(RemoteFrameCodec.encode(sealed))
    }

    private func handleSessionFrame(_ frame: Data, key: SymmetricKey) {
        guard let opened = try? RemoteSecureChannel.open(frame, using: key),
              let message = try? RemoteMessageCodec.decode(opened)
        else { return }

        switch message {
        case let .snapshot(snapshot):
            self.snapshot = snapshot
            serverProtocolVersion = snapshot.serverProtocolVersion ?? 1
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            state = .connected
            sendPushRegistration()
        case let .paneContent(
            paneID, text, cursorRow, cursorColumn, styledLines, altScreen
        ):
            paneContent[paneID] = PaneScreen(
                text: text,
                cursorRow: cursorRow,
                cursorColumn: cursorColumn,
                styledLines: styledLines ?? [],
                altScreen: altScreen ?? false
            )
        case let .paneSchedules(paneID, schedules):
            paneSchedules[paneID] = schedules
        default:
            break
        }
    }

    private func handleSessionClose(_ error: Error?) {
        transport = nil
        sessionKey = nil
        if let error {
            state = .failed("\(error)")
        } else {
            state = .disconnected
        }
    }

    /// Hands the Mac this device's relay registration. Sent on every
    /// connection because iOS can issue a different APNs token at any
    /// launch, and with an empty id when permission is missing so the Mac
    /// stops pushing to a device that would silently drop the alerts.
    private func sendPushRegistration() {
        guard state == .connected, serverProtocolVersion >= 3 else { return }
        send(
            .registerPushRelay(
                pushID: pushRegistration.registration?.pushID ?? "",
                relaySecretBase64: pushRegistration.registration?.relaySecret
                    ?? ""
            )
        )
    }

    private func send(_ message: RemoteMessage) {
        guard let sessionKey,
              let payload = try? RemoteMessageCodec.encode(message),
              let sealed = try? RemoteSecureChannel.seal(payload, using: sessionKey)
        else { return }
        transport?.send(RemoteFrameCodec.encode(sealed))
    }
}
