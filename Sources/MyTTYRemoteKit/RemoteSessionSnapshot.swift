import Foundation

public enum RemotePaneKind: String, Codable, Equatable, Sendable {
    case terminal
    case browser
}

/// What the host knows about the agent running in a pane. Every field is
/// optional and absent from servers older than protocol version 5, so a
/// client must treat "no agent status" and "an older host" the same way:
/// show nothing rather than guess.
///
/// This is the host's own view — the same values its status bar draws —
/// rather than anything a client could derive. A client cannot see the
/// pane's foreground process or read its transcript, so without this it
/// would have no way to tell a busy agent from an idle shell.
public struct RemotePaneAgentStatus: Codable, Equatable, Sendable {
    /// The provider's stable identifier ("codex", "claude-code", …).
    public var provider: String?
    /// The run state the host's reducer derived ("running", "waiting", …).
    public var state: String?
    public var modelName: String?
    /// 0–100. Already clamped by the host's inspector.
    public var contextRemainingPercent: Double?
    /// True when the host has an unacknowledged, actionable Attention item
    /// for this pane. Deliberately a flag rather than the item itself: a
    /// client cannot acknowledge on the host's behalf, so anything richer
    /// would imply an interaction that does not exist.
    public var needsAttention: Bool

    public init(
        provider: String? = nil,
        state: String? = nil,
        modelName: String? = nil,
        contextRemainingPercent: Double? = nil,
        needsAttention: Bool = false
    ) {
        self.provider = provider
        self.state = state
        self.modelName = modelName
        self.contextRemainingPercent = contextRemainingPercent
        self.needsAttention = needsAttention
    }

    /// Nothing worth showing: no agent, and nothing waiting on the user.
    public var isEmpty: Bool {
        provider == nil && state == nil && modelName == nil
            && contextRemainingPercent == nil && !needsAttention
    }

    private enum CodingKeys: String, CodingKey {
        case provider = "p"
        case state = "s"
        case modelName = "m"
        case contextRemainingPercent = "c"
        case needsAttention = "a"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        modelName = try container.decodeIfPresent(
            String.self,
            forKey: .modelName
        )
        contextRemainingPercent = try container.decodeIfPresent(
            Double.self,
            forKey: .contextRemainingPercent
        )
        needsAttention = try container.decodeIfPresent(
            Bool.self,
            forKey: .needsAttention
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encodeIfPresent(
            contextRemainingPercent,
            forKey: .contextRemainingPercent
        )
        if needsAttention {
            try container.encode(needsAttention, forKey: .needsAttention)
        }
    }
}

public struct RemotePane: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var command: String
    public var location: String
    public var kind: RemotePaneKind
    public var isActive: Bool
    /// Absent from hosts older than protocol version 5.
    public var agent: RemotePaneAgentStatus?

    public init(
        id: String,
        title: String,
        command: String,
        location: String,
        kind: RemotePaneKind,
        isActive: Bool,
        agent: RemotePaneAgentStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.location = location
        self.kind = kind
        self.isActive = isActive
        self.agent = agent
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
