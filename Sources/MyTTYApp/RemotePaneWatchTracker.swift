import Foundation
import MyTTYRemoteKit

/// What a remote client sees of one pane: its visible text plus the
/// cursor's zero-based viewport coordinates (nil for panes without a
/// cursor, such as browser panes). `styledLines` carries the same content
/// with resolved colors, bottom-aligned to `text`; empty for panes without
/// color (e.g. browser panes).
struct RemotePaneContent: Equatable {
    var text: String
    var cursorRow: Int?
    var cursorColumn: Int?
    var styledLines: [RemoteStyledLine] = []
    /// True when the pane only has a screen-sized buffer (alternate-screen
    /// TUI): the client scrolls it remotely via `scrollPane` instead of
    /// scrolling a mirrored scrollback.
    var altScreen = false
}

/// Tracks which panes a single remote connection is watching and the last
/// content sent for each, so polling only pushes `paneContent` frames when
/// the pane's visible text or cursor actually changed.
struct RemotePaneWatchTracker {
    private(set) var watchedPaneIDs: Set<String> = []
    private var lastSent: [String: RemotePaneContent] = [:]

    mutating func watch(paneID: String) {
        watchedPaneIDs.insert(paneID)
    }

    mutating func unwatch(paneID: String) {
        watchedPaneIDs.remove(paneID)
        lastSent.removeValue(forKey: paneID)
    }

    /// Returns the content that should be sent for `paneID`, or `nil` if
    /// the pane isn't watched or nothing changed since the last send.
    mutating func contentToSend(
        paneID: String,
        current: RemotePaneContent
    ) -> RemotePaneContent? {
        guard watchedPaneIDs.contains(paneID) else { return nil }
        guard lastSent[paneID] != current else { return nil }
        lastSent[paneID] = current
        return current
    }
}
