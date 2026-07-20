import GhosttyAdapter
import MyTTYCore

/// Bridges the iOS remote's per-pane read/write surface: turning a pane's
/// live terminal state into a `RemotePaneContent` snapshot, and delivering
/// remote-typed text/key events back into the matching `GhosttySurfaceView`.
/// Extracted from `TerminalWindowController.remotePaneContent` /
/// `deliverRemoteInput` / `deliverRemoteKey` / `setRemoteAccessConnected`
/// verbatim.
///
/// `RemoteAccessServer` (via `AppDelegate`'s `RemoteAccessServerDelegate`
/// conformance) calls these four methods directly on
/// `TerminalWindowController`, so the controller keeps thin public
/// forwarders with the original names/signatures; this type holds the
/// actual logic. `RemotePaneWatchTracker`/`RemoteScrollback` stay exactly
/// where they were — the former is owned by `RemoteAccessServer`, and the
/// latter is a stateless formatter this bridge calls into, same as before.
@MainActor
final class RemotePaneBridge {
    private let surface: (TerminalSurfaceID) -> GhosttySurfaceView?
    /// Fired when the remote's connection state changes — the controller
    /// uses this to update the sidebar's "remote connected" indicator.
    private let onConnectedChanged: (Bool) -> Void

    init(
        surface: @escaping (TerminalSurfaceID) -> GhosttySurfaceView?,
        onConnectedChanged: @escaping (Bool) -> Void
    ) {
        self.surface = surface
        self.onConnectedChanged = onConnectedChanged
    }

    func setConnected(_ connected: Bool) {
        onConnectedChanged(connected)
    }

    func content(forPane paneID: TerminalSurfaceID) -> RemotePaneContent? {
        guard let surface = surface(paneID) else { return nil }
        let cursor = surface.terminalCursorPosition
        let gridSize = surface.terminalGridSize
        return RemoteScrollback.content(
            screenText: surface.screenText(),
            viewportText: surface.visibleText(),
            viewportCursor: cursor.map { ($0.row, $0.column) },
            gridColumns: gridSize.columns,
            gridRows: gridSize.rows,
            styledLines: RemoteVTStyledParser.parse(surface.screenVTText())
        )
    }

    @discardableResult
    func deliverScroll(
        paneID: TerminalSurfaceID,
        deltaY: Double
    ) -> Bool {
        guard let surface = surface(paneID) else { return false }
        surface.sendScroll(deltaY: deltaY)
        return true
    }

    @discardableResult
    func deliverInput(
        paneID: TerminalSurfaceID,
        text: String,
        pressEnter: Bool
    ) -> Bool {
        guard let surface = surface(paneID) else { return false }
        surface.sendText(text)
        if pressEnter {
            surface.sendEnter()
        }
        return true
    }

    @discardableResult
    func deliverKey(
        paneID: TerminalSurfaceID,
        event: RemoteKeyMapping.KeyEvent
    ) -> Bool {
        guard let surface = surface(paneID) else { return false }
        surface.sendKeyPress(
            keyCode: event.keyCode,
            characters: event.characters,
            modifierFlags: event.modifierFlags
        )
        return true
    }
}
