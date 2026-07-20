import Foundation

/// A pane or tab captured just before it closed, with enough state
/// (scrollback, working directory, agent resume) to reopen it later.
public enum ClosedPaneRecord: Equatable, Sendable {
    case terminal(TerminalSurfaceState)
    case browser(BrowserPaneState)
    case tab(TabSession)
}

public struct ClosedPaneHistoryEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let record: ClosedPaneRecord
    public let closedAt: Date

    public init(
        id: UUID = UUID(),
        record: ClosedPaneRecord,
        closedAt: Date = Date()
    ) {
        self.id = id
        self.record = record
        self.closedAt = closedAt
    }
}

/// In-memory, LIFO stack of recently closed panes/tabs for the running
/// session. Never persisted: it exists so "reopen closed item" works while
/// the app is open, and is discarded on quit (the separate end-of-life
/// session snapshot already covers restart restoration).
@MainActor
public final class ClosedPaneHistory {
    public static let capacity = 20

    public private(set) var entries: [ClosedPaneHistoryEntry] = []

    public init() {}

    public func push(_ record: ClosedPaneRecord) {
        entries.insert(ClosedPaneHistoryEntry(record: record), at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    @discardableResult
    public func popMostRecent() -> ClosedPaneHistoryEntry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    @discardableResult
    public func remove(id: UUID) -> ClosedPaneHistoryEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return entries.remove(at: index)
    }
}

extension TerminalSurfaceState {
    func withID(_ id: TerminalSurfaceID) -> TerminalSurfaceState {
        TerminalSurfaceState(
            id: id,
            workingDirectory: workingDirectory,
            agentResume: agentResume,
            terminalHistory: terminalHistory
        )
    }

    public func regeneratingID() -> TerminalSurfaceState {
        withID(TerminalSurfaceID())
    }
}

extension BrowserPaneState {
    func withID(_ id: TerminalSurfaceID) -> BrowserPaneState {
        BrowserPaneState(id: id, url: url)
    }

    public func regeneratingID() -> BrowserPaneState {
        withID(TerminalSurfaceID())
    }
}

extension TabSession {
    /// Rebuilds this tab with a fresh `TabID` and a fresh ID for every
    /// pane, preserving layout (orientation/ratio), scrollback, and
    /// resume info. Used when reopening a closed tab so it cannot collide
    /// with stale references (e.g. in `AttentionCenter`) to the IDs it
    /// closed with.
    public func regeneratingIDs() -> TabSession {
        var idMap: [TerminalSurfaceID: TerminalSurfaceID] = [:]
        root.collectPaneIDs(into: &idMap)
        let newRoot = root.regeneratingIDs(using: idMap)
        let newFocusedSurfaceID = idMap[focusedSurfaceID]
            ?? newRoot.paneIDs.first
            ?? focusedSurfaceID
        return TabSession(
            root: newRoot,
            focusedSurfaceID: newFocusedSurfaceID,
            pinnedTitle: pinnedTitle
        )
    }
}

private extension SplitNode {
    func collectPaneIDs(
        into map: inout [TerminalSurfaceID: TerminalSurfaceID]
    ) {
        switch self {
        case let .surface(state):
            map[state.id] = TerminalSurfaceID()
        case let .browser(state):
            map[state.id] = TerminalSurfaceID()
        case let .split(_, _, first, second):
            first.collectPaneIDs(into: &map)
            second.collectPaneIDs(into: &map)
        }
    }

    func regeneratingIDs(
        using map: [TerminalSurfaceID: TerminalSurfaceID]
    ) -> SplitNode {
        switch self {
        case let .surface(state):
            .surface(state.withID(map[state.id] ?? state.id))
        case let .browser(state):
            .browser(state.withID(map[state.id] ?? state.id))
        case let .split(orientation, ratio, first, second):
            .split(
                orientation: orientation,
                ratio: ratio,
                first: first.regeneratingIDs(using: map),
                second: second.regeneratingIDs(using: map)
            )
        }
    }
}
