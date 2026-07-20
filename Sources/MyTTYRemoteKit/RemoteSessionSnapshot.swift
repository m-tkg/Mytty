import Foundation

public enum RemotePaneKind: String, Codable, Equatable, Sendable {
    case terminal
    case browser
}

public struct RemotePane: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var command: String
    public var location: String
    public var kind: RemotePaneKind
    public var isActive: Bool

    public init(
        id: String,
        title: String,
        command: String,
        location: String,
        kind: RemotePaneKind,
        isActive: Bool
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.location = location
        self.kind = kind
        self.isActive = isActive
    }
}

public struct RemoteTab: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var panes: [RemotePane]

    public init(id: String, title: String, panes: [RemotePane]) {
        self.id = id
        self.title = title
        self.panes = panes
    }
}

public struct RemoteWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var tabs: [RemoteTab]

    public init(id: String, tabs: [RemoteTab]) {
        self.id = id
        self.tabs = tabs
    }
}

public struct RemoteSessionSnapshot: Codable, Equatable, Sendable {
    public var windows: [RemoteWindow]
    /// The protocol version the Mac speaks. Absent from servers older than
    /// version 2, which is how a client tells that messages introduced
    /// later (`registerPushToken`) would fail to decode there — those
    /// servers close the connection on an unknown message type, so the
    /// client must stay silent rather than probe.
    public var serverProtocolVersion: Int?

    public init(windows: [RemoteWindow], serverProtocolVersion: Int? = nil) {
        self.windows = windows
        self.serverProtocolVersion = serverProtocolVersion
    }
}

public struct RemotePaneLocation: Equatable, Hashable, Sendable {
    public let windowID: String
    public let tabID: String
    public let paneID: String

    public init(windowID: String, tabID: String, paneID: String) {
        self.windowID = windowID
        self.tabID = tabID
        self.paneID = paneID
    }
}

/// Lookups by ID, so a view holding on to a window/tab/pane it was pushed
/// with can re-resolve it against the newest snapshot — and tell that it
/// went away on the Mac.
public extension RemoteSessionSnapshot {
    func window(withID id: String) -> RemoteWindow? {
        windows.first { $0.id == id }
    }

    func tab(withID id: String) -> RemoteTab? {
        for window in windows {
            if let match = window.tabs.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// Where a pane sits, so a client holding only a pane ID — an
    /// Attention push carries nothing else — can rebuild the whole path
    /// to it.
    func location(ofPaneID id: String) -> RemotePaneLocation? {
        for window in windows {
            for tab in window.tabs where tab.panes.contains(where: {
                $0.id == id
            }) {
                return RemotePaneLocation(
                    windowID: window.id,
                    tabID: tab.id,
                    paneID: id
                )
            }
        }
        return nil
    }

    func pane(withID id: String) -> RemotePane? {
        for window in windows {
            for tab in window.tabs {
                if let match = tab.panes.first(where: { $0.id == id }) {
                    return match
                }
            }
        }
        return nil
    }
}
