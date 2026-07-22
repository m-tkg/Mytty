import Foundation

public enum RemoteMessage: Equatable, Sendable {
    case pairRequest(deviceName: String, code: String)
    case pairApproved(deviceID: String, deviceSecretBase64: String)
    /// Authenticity is proven by the caller successfully decrypting the
    /// frame carrying this message with the device's stored secret, so no
    /// secret is ever placed in the payload itself.
    case hello(deviceID: String, protocolVersion: Int)
    case snapshot(RemoteSessionSnapshot)
    case watchPane(paneID: String)
    case unwatchPane(paneID: String)
    /// Cursor coordinates are zero-based viewport row/column; nil when
    /// the pane has no known cursor (e.g. a browser pane). `styledLines`
    /// carries the same content with resolved colors, bottom-aligned to
    /// `text`; nil or shorter than `text` means the unstyled top lines
    /// render without color (older clients ignore it entirely).
    /// `altScreen` is true when the pane is showing only a screen-sized
    /// buffer (an alternate-screen TUI): the client should forward scroll
    /// gestures via `scrollPane` instead of scrolling locally. nil from
    /// older servers.
    case paneContent(
        paneID: String,
        text: String,
        cursorRow: Int?,
        cursorColumn: Int?,
        styledLines: [RemoteStyledLine]?,
        altScreen: Bool?
    )
    case sendInput(paneID: String, text: String, pressEnter: Bool)
    /// Scrolls a pane remotely. `deltaY` is in wheel lines (positive =
    /// toward older content), forwarded to the terminal as mouse-wheel
    /// input so full-screen TUIs (which have no scrollback to mirror)
    /// scroll their own view.
    case scrollPane(paneID: String, deltaY: Double)
    /// A discrete keystroke (named key such as "escape"/"up"/"f1", or a
    /// single character) delivered on the Mac as a synthesized key event
    /// rather than injected text, so TUIs using the kitty keyboard
    /// protocol see a real key press. Modifier names: "shift",
    /// "control", "option", "command".
    case sendKey(paneID: String, key: String, modifiers: [String])
    case newTab(windowID: String)
    /// Sent by protocol-2 clients, which pushed through a provider key on
    /// the Mac. Retained only so those clients still decode against a
    /// current Mac (an unknown message type closes the connection); the
    /// server ignores it.
    case registerPushToken(token: String, bundleID: String, environment: String)
    /// Registers this device for Attention push notifications. The phone
    /// exchanges its APNs token with the relay itself and passes on only
    /// the resulting handle, so the Mac never learns the device token and
    /// the relay never learns the pairing key. An empty `pushID` means
    /// "stop pushing to me". Older servers close the connection on this,
    /// which is why clients gate it on the version in the snapshot.
    case registerPushRelay(pushID: String, relaySecretBase64: String)
    /// Asks the Mac for the pane's currently scheduled inputs.
    case listPaneSchedules(paneID: String)
    /// Reply to `listPaneSchedules` (and to `createPaneSchedule` /
    /// `deletePaneSchedule`, which both answer with the fresh list rather
    /// than a bespoke ack).
    case paneSchedules(paneID: String, schedules: [RemotePaneSchedule])
    /// `schedule.id` is client-generated so the phone can address it before
    /// the round trip completes. The Mac silently ignores requests for an
    /// unknown pane or a past `fireAt`; the reply list simply won't
    /// contain it.
    case createPaneSchedule(paneID: String, schedule: RemotePaneSchedule)
    case deletePaneSchedule(paneID: String, scheduleID: String)
    case failure(code: String)
}

extension RemoteMessage: Codable {
    private enum MessageType: String, Codable {
        case pairRequest
        case pairApproved
        case hello
        case snapshot
        case watchPane
        case unwatchPane
        case paneContent
        case sendInput
        case scrollPane
        case sendKey
        case newTab
        case registerPushToken
        case registerPushRelay
        case listPaneSchedules
        case paneSchedules
        case createPaneSchedule
        case deletePaneSchedule
        case failure
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case deviceName
        case code
        case deviceID
        case deviceSecretBase64
        case protocolVersion
        case snapshot
        case paneID
        case text
        case pressEnter
        case windowID
        case key
        case modifiers
        case token
        case bundleID
        case environment
        case pushID
        case relaySecretBase64
        case cursorRow
        case cursorColumn
        case styledLines
        case altScreen
        case deltaY
        case schedules
        case schedule
        case scheduleID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .pairRequest:
            self = .pairRequest(
                deviceName: try container.decode(String.self, forKey: .deviceName),
                code: try container.decode(String.self, forKey: .code)
            )
        case .pairApproved:
            self = .pairApproved(
                deviceID: try container.decode(String.self, forKey: .deviceID),
                deviceSecretBase64: try container.decode(
                    String.self,
                    forKey: .deviceSecretBase64
                )
            )
        case .hello:
            self = .hello(
                deviceID: try container.decode(String.self, forKey: .deviceID),
                protocolVersion: try container.decode(Int.self, forKey: .protocolVersion)
            )
        case .snapshot:
            self = .snapshot(
                try container.decode(RemoteSessionSnapshot.self, forKey: .snapshot)
            )
        case .watchPane:
            self = .watchPane(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .unwatchPane:
            self = .unwatchPane(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .paneContent:
            self = .paneContent(
                paneID: try container.decode(String.self, forKey: .paneID),
                text: try container.decode(String.self, forKey: .text),
                cursorRow: try container.decodeIfPresent(
                    Int.self,
                    forKey: .cursorRow
                ),
                cursorColumn: try container.decodeIfPresent(
                    Int.self,
                    forKey: .cursorColumn
                ),
                styledLines: try container.decodeIfPresent(
                    [RemoteStyledLine].self,
                    forKey: .styledLines
                ),
                altScreen: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .altScreen
                )
            )
        case .scrollPane:
            self = .scrollPane(
                paneID: try container.decode(String.self, forKey: .paneID),
                deltaY: try container.decode(Double.self, forKey: .deltaY)
            )
        case .sendInput:
            self = .sendInput(
                paneID: try container.decode(String.self, forKey: .paneID),
                text: try container.decode(String.self, forKey: .text),
                pressEnter: try container.decode(Bool.self, forKey: .pressEnter)
            )
        case .sendKey:
            self = .sendKey(
                paneID: try container.decode(String.self, forKey: .paneID),
                key: try container.decode(String.self, forKey: .key),
                modifiers: try container.decode([String].self, forKey: .modifiers)
            )
        case .newTab:
            self = .newTab(
                windowID: try container.decode(String.self, forKey: .windowID)
            )
        case .registerPushToken:
            self = .registerPushToken(
                token: try container.decode(String.self, forKey: .token),
                bundleID: try container.decode(String.self, forKey: .bundleID),
                environment: try container.decode(
                    String.self,
                    forKey: .environment
                )
            )
        case .registerPushRelay:
            self = .registerPushRelay(
                pushID: try container.decode(String.self, forKey: .pushID),
                relaySecretBase64: try container.decode(
                    String.self,
                    forKey: .relaySecretBase64
                )
            )
        case .listPaneSchedules:
            self = .listPaneSchedules(
                paneID: try container.decode(String.self, forKey: .paneID)
            )
        case .paneSchedules:
            self = .paneSchedules(
                paneID: try container.decode(String.self, forKey: .paneID),
                schedules: try container.decode(
                    [RemotePaneSchedule].self,
                    forKey: .schedules
                )
            )
        case .createPaneSchedule:
            self = .createPaneSchedule(
                paneID: try container.decode(String.self, forKey: .paneID),
                schedule: try container.decode(
                    RemotePaneSchedule.self,
                    forKey: .schedule
                )
            )
        case .deletePaneSchedule:
            self = .deletePaneSchedule(
                paneID: try container.decode(String.self, forKey: .paneID),
                scheduleID: try container.decode(
                    String.self,
                    forKey: .scheduleID
                )
            )
        case .failure:
            self = .failure(
                code: try container.decode(String.self, forKey: .code)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pairRequest(deviceName, code):
            try container.encode(MessageType.pairRequest, forKey: .type)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encode(code, forKey: .code)
        case let .pairApproved(deviceID, deviceSecretBase64):
            try container.encode(MessageType.pairApproved, forKey: .type)
            try container.encode(deviceID, forKey: .deviceID)
            try container.encode(
                deviceSecretBase64,
                forKey: .deviceSecretBase64
            )
        case let .hello(deviceID, protocolVersion):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(deviceID, forKey: .deviceID)
            try container.encode(protocolVersion, forKey: .protocolVersion)
        case let .snapshot(snapshot):
            try container.encode(MessageType.snapshot, forKey: .type)
            try container.encode(snapshot, forKey: .snapshot)
        case let .watchPane(paneID):
            try container.encode(MessageType.watchPane, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case let .unwatchPane(paneID):
            try container.encode(MessageType.unwatchPane, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case let .paneContent(
            paneID,
            text,
            cursorRow,
            cursorColumn,
            styledLines,
            altScreen
        ):
            try container.encode(MessageType.paneContent, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(cursorRow, forKey: .cursorRow)
            try container.encodeIfPresent(cursorColumn, forKey: .cursorColumn)
            try container.encodeIfPresent(styledLines, forKey: .styledLines)
            try container.encodeIfPresent(altScreen, forKey: .altScreen)
        case let .scrollPane(paneID, deltaY):
            try container.encode(MessageType.scrollPane, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(deltaY, forKey: .deltaY)
        case let .sendInput(paneID, text, pressEnter):
            try container.encode(MessageType.sendInput, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(text, forKey: .text)
            try container.encode(pressEnter, forKey: .pressEnter)
        case let .sendKey(paneID, key, modifiers):
            try container.encode(MessageType.sendKey, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(key, forKey: .key)
            try container.encode(modifiers, forKey: .modifiers)
        case let .newTab(windowID):
            try container.encode(MessageType.newTab, forKey: .type)
            try container.encode(windowID, forKey: .windowID)
        case let .registerPushToken(token, bundleID, environment):
            try container.encode(MessageType.registerPushToken, forKey: .type)
            try container.encode(token, forKey: .token)
            try container.encode(bundleID, forKey: .bundleID)
            try container.encode(environment, forKey: .environment)
        case let .registerPushRelay(pushID, relaySecretBase64):
            try container.encode(MessageType.registerPushRelay, forKey: .type)
            try container.encode(pushID, forKey: .pushID)
            try container.encode(
                relaySecretBase64,
                forKey: .relaySecretBase64
            )
        case let .listPaneSchedules(paneID):
            try container.encode(MessageType.listPaneSchedules, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
        case let .paneSchedules(paneID, schedules):
            try container.encode(MessageType.paneSchedules, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(schedules, forKey: .schedules)
        case let .createPaneSchedule(paneID, schedule):
            try container.encode(MessageType.createPaneSchedule, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(schedule, forKey: .schedule)
        case let .deletePaneSchedule(paneID, scheduleID):
            try container.encode(MessageType.deletePaneSchedule, forKey: .type)
            try container.encode(paneID, forKey: .paneID)
            try container.encode(scheduleID, forKey: .scheduleID)
        case let .failure(code):
            try container.encode(MessageType.failure, forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }
}

public enum RemoteMessageCodec {
    /// 2 added `registerPushToken` (and the `serverProtocolVersion` field
    /// on `RemoteSessionSnapshot` that lets a client detect it); 3
    /// replaced it with `registerPushRelay` when pushes moved off a
    /// provider key on the Mac and onto the relay; 4 added the
    /// pane-schedule messages.
    public static let protocolVersion = 4

    /// JSON payload only. Wire framing (and, for authenticated
    /// connections, encryption) is applied by `RemoteFrameCodec` /
    /// `RemoteSecureChannel` around this payload.
    public static func encode(_ message: RemoteMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    public static func decode(_ data: Data) throws -> RemoteMessage {
        try JSONDecoder().decode(RemoteMessage.self, from: data)
    }
}
