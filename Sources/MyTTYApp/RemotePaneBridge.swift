import Dispatch
import GhosttyAdapter
import MyTTYCore

/// `sendText`/`sendEnter` already match `RemoteInputDeliverable` — this
/// just tells the type system so `PaneInputDeliveryQueue` can drive a real
/// `GhosttySurfaceView` without knowing about it directly.
extension GhosttySurfaceView: RemoteInputDeliverable {}

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
    /// Per-pane serialization for `deliverInput` — see
    /// `PaneInputDeliveryQueue` for why a naive synchronous send plus a
    /// delayed Enter isn't enough once a pane receives back-to-back calls.
    private let inputQueue: PaneInputDeliveryQueue<GhosttySurfaceView>

    init(
        surface: @escaping (TerminalSurfaceID) -> GhosttySurfaceView?,
        onConnectedChanged: @escaping (Bool) -> Void
    ) {
        self.surface = surface
        self.onConnectedChanged = onConnectedChanged
        self.inputQueue = PaneInputDeliveryQueue(
            enterDelay: Self.enterDeliveryDelay,
            target: surface
        )
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

    /// Delay between delivering text and the follow-up Enter keystroke.
    ///
    /// Cursor Agent's TUI treats a same-runloop-turn text+Enter burst as a
    /// paste and drops the Enter, leaving the text sitting unsent in the
    /// input box (reproduced against the real app: `send --enter` landed
    /// the text but never submitted it, while a separate `send-key return`
    /// right after submitted immediately). Codex and Claude Code both
    /// accept the same-turn burst fine, but there's no reliable way to
    /// detect "is this pane's foreground process Cursor" from here without
    /// reaching back into agent-provider detection, so we apply the delay
    /// unconditionally — a fixed 50ms is imperceptible for a keystroke and
    /// keeps this path provider-agnostic.
    static let enterDeliveryDelay: DispatchTimeInterval = .milliseconds(50)

    @discardableResult
    func deliverInput(
        paneID: TerminalSurfaceID,
        text: String,
        pressEnter: Bool
    ) -> Bool {
        // `false` still means "no such pane". `true` means the pane exists
        // and the input was accepted for delivery — it may not have been
        // sent synchronously: `inputQueue` defers text behind a pane's
        // still-pending Enter (see `enterDeliveryDelay`) so a fast
        // follow-up call can't overtake it and scramble the order the PTY
        // sees. Callers that need "already delivered" can't read that off
        // this return value.
        inputQueue.deliver(paneID: paneID, text: text, pressEnter: pressEnter)
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
