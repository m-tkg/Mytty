import Combine
import CryptoKit
import Foundation
import Network

public enum RemoteClientError: Error {
    case connectionClosed
    case protocolError
    case noEndpoint
    case cancelled
    case timedOut
}

/// A client session against one Mac's remote-access server: pairing,
/// reconnecting, mirroring pane content, and sending input back. Shared by
/// the iOS remote app and by a Mac hosting remote panes, so nothing here
/// may touch UIKit or AppKit.
@MainActor
public final class RemoteClient: ObservableObject {
    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    public struct PaneScreen: Equatable {
        public var text: String
        public var cursorRow: Int?
        public var cursorColumn: Int?
        /// Colored lines bottom-aligned to `text`; empty or shorter than
        /// `text` means the top lines render without color.
        public var styledLines: [RemoteStyledLine] = []
        /// True when the pane only has a screen-sized buffer (an
        /// alternate-screen TUI): scroll gestures are forwarded to the
        /// Mac instead of scrolling the mirrored text locally.
        public var altScreen = false

        public init(
            text: String,
            cursorRow: Int? = nil,
            cursorColumn: Int? = nil,
            styledLines: [RemoteStyledLine] = [],
            altScreen: Bool = false
        ) {
            self.text = text
            self.cursorRow = cursorRow
            self.cursorColumn = cursorColumn
            self.styledLines = styledLines
            self.altScreen = altScreen
        }
    }

    @Published public private(set) var state: ConnectionState = .disconnected
    @Published public private(set) var snapshot: RemoteSessionSnapshot?
    @Published public private(set) var paneContent: [String: PaneScreen] = [:]
    @Published public private(set) var paneSchedules: [String: [RemotePaneSchedule]] = [:]

    public var isConnected: Bool { state == .connected }

    /// True once the connected Mac has confirmed it understands the
    /// pane-schedule messages; older servers close the connection on an
    /// unknown message type, so callers must gate on this before sending.
    public var supportsPaneSchedules: Bool { serverProtocolVersion >= 4 }

    /// True once the connected Mac reports the agent status and attention
    /// fields on each pane. Older servers simply leave them nil, so this is
    /// only needed where the absence has to be told apart from "no agent".
    public var supportsPaneAgentStatus: Bool { serverProtocolVersion >= 5 }

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
    public static let attemptTimeout: Duration = .seconds(30)
    private var pairingEndpointInfo: (macName: String, host: String?, port: UInt16?)?
    private var pairingLabel = ""
    private let pushRegistration: RemotePushRegistrationProviding?
    private var pushRegistrationObserver: AnyCancellable?
    /// The version reported by the connected Mac, so features added after
    /// version 1 are only used where they will decode. Older servers close
    /// the connection on an unknown message type.
    private var serverProtocolVersion = 1

    public init(pushRegistration: RemotePushRegistrationProviding? = nil) {
        self.pushRegistration = pushRegistration
        // The token can land after the session is already up (first launch
        // asks for permission), so re-send whenever it changes.
        pushRegistrationObserver = pushRegistration?
            .pushRelayRegistrationChanged
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sendPushRegistration()
                }
            }
    }

    // MARK: Pairing

    public func pair(
        macName: String?,
        endpoint: NWEndpoint,
        token: String,
        deviceName: String,
        label: String
    ) async throws -> PairedMac {
        disconnect()
        let key = RemotePairing.derivePresharedKey(token: token)
        pairingEndpointInfo = addressingInfo(macName: macName, endpoint: endpoint)
        pairingLabel = label

        let transport = RemoteConnectionTransport(endpoint: endpoint)
        self.transport = transport

        transport.onReady = { [weak self] in
            Task { @MainActor [weak self] in
                self?.sendPairRequest(deviceName: deviceName, token: token, key: key)
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
    public func cancelPairing() {
        failPairing(RemoteClientError.cancelled)
        transport?.cancel()
        transport = nil
    }

    private func sendPairRequest(
        deviceName: String,
        token: String,
        key: SymmetricKey
    ) {
        guard let payload = try? RemoteMessageCodec.encode(
            .pairRequest(deviceName: deviceName, token: token)
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

    public func connect(mac: PairedMac) {
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
    public func reconnect() {
        guard let mac = lastConnectedMac else { return }
        connect(mac: mac)
    }

    public var canReconnect: Bool { lastConnectedMac != nil }

    /// Lets a caller tell whether the session already on screen is the
    /// one it wants, rather than reconnecting and throwing away a live
    /// connection along with the pane content it has already mirrored.
    public var connectedMacID: String? { lastConnectedMac?.deviceID }

    /// The label the user gave the connected Mac, for chrome that has to
    /// say which machine a pane is mirroring.
    public var connectedMacDisplayName: String? {
        lastConnectedMac?.displayName
    }

    public func disconnect() {
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

    public func watchPane(_ paneID: String) {
        send(.watchPane(paneID: paneID))
    }

    public func unwatchPane(_ paneID: String) {
        send(.unwatchPane(paneID: paneID))
    }

    /// `paste` tells the Mac whether to deliver the text as a clipboard
    /// paste or as typed keyboard input; typed is the default because
    /// everything but the paste key comes from the on-screen keyboard.
    public func sendInput(
        paneID: String,
        text: String,
        pressEnter: Bool,
        paste: Bool = false
    ) {
        send(
            .sendInput(
                paneID: paneID,
                text: text,
                pressEnter: pressEnter,
                paste: paste
            )
        )
    }

    public func sendKey(paneID: String, key: String, modifiers: [String]) {
        send(.sendKey(paneID: paneID, key: key, modifiers: modifiers))
    }

    /// Forwards a scroll gesture to an alternate-screen pane as
    /// mouse-wheel lines (positive = toward older content).
    public func sendScroll(paneID: String, deltaY: Double) {
        send(.scrollPane(paneID: paneID, deltaY: deltaY))
    }

    public func newTab(windowID: String) {
        send(.newTab(windowID: windowID))
    }

    public func requestPaneSchedules(paneID: String) {
        guard state == .connected, supportsPaneSchedules else { return }
        send(.listPaneSchedules(paneID: paneID))
    }

    /// Sends a client-generated schedule and returns its ID so the caller
    /// can recognize it in a later `paneSchedules` reply (or notice its
    /// absence — the Mac silently drops an unknown pane or a past date
    /// rather than replying with an error).
    @discardableResult
    public func createPaneSchedule(
        paneID: String,
        fireAt: Date,
        text: String,
        pressEnter: Bool
    ) -> String {
        let id = UUID().uuidString
        guard state == .connected, supportsPaneSchedules else { return id }
        send(
            .createPaneSchedule(
                paneID: paneID,
                schedule: RemotePaneSchedule(
                    id: id,
                    fireAt: fireAt,
                    text: text,
                    pressEnter: pressEnter
                )
            )
        )
        return id
    }

    public func deletePaneSchedule(paneID: String, scheduleID: String) {
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
    /// A client with no push provider at all (a Mac) sends nothing.
    private func sendPushRegistration() {
        guard let pushRegistration else { return }
        guard state == .connected, serverProtocolVersion >= 3 else { return }
        let registration = pushRegistration.currentPushRelayRegistration
        send(
            .registerPushRelay(
                pushID: registration?.pushID ?? "",
                relaySecretBase64: registration?.relaySecret ?? ""
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
