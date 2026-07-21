import Dispatch
import MyTTYCore

/// Minimal capability `PaneInputDeliveryQueue` needs from a pane surface —
/// split out from `GhosttySurfaceView`'s full API so per-pane input
/// ordering can be unit tested against a fake, without constructing a real
/// Ghostty-backed surface.
@MainActor
protocol RemoteInputDeliverable: AnyObject {
    func sendText(_ text: String)
    func sendEnter()
}

/// Serializes `text`/`pressEnter` deliveries per pane so a burst of
/// `deliver` calls to the same pane can never land out of order at the PTY.
///
/// Background: a plain text send is synchronous, but a `pressEnter` send
/// schedules its Enter keystroke on a later runloop turn (see
/// `RemotePaneBridge.enterDeliveryDelay`) so Cursor Agent's TUI doesn't
/// coalesce it into the preceding paste. If a second `deliver` for the same
/// pane arrived while that Enter was still in flight, its text used to jump
/// the queue and land at the PTY *before* the first call's Enter — e.g.
/// `deliver("A", pressEnter: true)` immediately followed by
/// `deliver("B", pressEnter: true)` produced "AB" at the shell followed by
/// two Enters, instead of "A", Enter, "B", Enter.
///
/// This type tracks, per pane, whether an Enter is currently pending; while
/// it is, later deliveries for that same pane are queued and replayed in
/// order once the pending Enter actually goes out. A pane with no pending
/// Enter still delivers text synchronously and immediately — this must stay
/// true so the iOS remote's per-keystroke latency doesn't regress.
@MainActor
final class PaneInputDeliveryQueue<Target: RemoteInputDeliverable> {
    private struct QueuedInput {
        let text: String
        let pressEnter: Bool
    }

    private let enterDelay: DispatchTimeInterval
    private let target: (TerminalSurfaceID) -> Target?

    /// Panes with an Enter keystroke scheduled but not yet delivered.
    private var pendingEnterPanes: Set<TerminalSurfaceID> = []
    /// Deliveries queued behind that pending Enter, oldest first.
    private var queuedByPane: [TerminalSurfaceID: [QueuedInput]] = [:]

    init(
        enterDelay: DispatchTimeInterval,
        target: @escaping (TerminalSurfaceID) -> Target?
    ) {
        self.enterDelay = enterDelay
        self.target = target
    }

    /// Accepts `text`/`pressEnter` for delivery to `paneID`.
    ///
    /// Returns `false` only when the pane doesn't currently exist. `true`
    /// means the pane exists and the input was accepted for delivery — not
    /// that it was necessarily sent synchronously: if a previous call's
    /// Enter for this pane is still pending, this input is queued behind it
    /// and delivered once that Enter fires. Callers that need to know when
    /// delivery actually happened can't infer it from this return value.
    @discardableResult
    func deliver(paneID: TerminalSurfaceID, text: String, pressEnter: Bool) -> Bool {
        guard let target = target(paneID) else { return false }
        guard !pendingEnterPanes.contains(paneID) else {
            queuedByPane[paneID, default: []].append(
                QueuedInput(text: text, pressEnter: pressEnter)
            )
            return true
        }
        send(to: target, paneID: paneID, text: text, pressEnter: pressEnter)
        return true
    }

    private func send(
        to target: Target,
        paneID: TerminalSurfaceID,
        text: String,
        pressEnter: Bool
    ) {
        target.sendText(text)
        guard pressEnter else { return }
        pendingEnterPanes.insert(paneID)
        // The weak captures mean a pane closed within the delay window
        // simply drops the keystroke instead of crashing; `drain` below
        // then discards anything still queued behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + enterDelay) { [weak self, weak target] in
            target?.sendEnter()
            self?.drain(paneID: paneID)
        }
    }

    private func drain(paneID: TerminalSurfaceID) {
        pendingEnterPanes.remove(paneID)
        guard var queue = queuedByPane[paneID], !queue.isEmpty else {
            queuedByPane.removeValue(forKey: paneID)
            return
        }
        let next = queue.removeFirst()
        if queue.isEmpty {
            queuedByPane.removeValue(forKey: paneID)
        } else {
            queuedByPane[paneID] = queue
        }
        guard let target = target(paneID) else {
            // Pane closed while input was queued behind the pending
            // Enter — drop the rest rather than delivering into thin air.
            queuedByPane.removeValue(forKey: paneID)
            return
        }
        send(to: target, paneID: paneID, text: next.text, pressEnter: next.pressEnter)
    }
}
