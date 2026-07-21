import Foundation
import MyTTYCore

/// Owns the wall-clock timer behind `CursorApprovalPendingTracker`. Cursor
/// never reports a shell command waiting on user permission, so this
/// watches for the gap after `beforeShellExecution` and, once it passes,
/// hands the synthetic `approval-requested` event to `deliver` — the same
/// path real hook events take (`AppDelegate.receiveAgentEvent`), so
/// focused-pane auto-ack, the phone push, and banner suppression all
/// apply to it unchanged.
@MainActor
final class CursorApprovalCoordinator: NSObject {
    private let tracker: CursorApprovalPendingTracker
    private let timerEnabled: Bool
    private let deliver: (AgentEvent) -> Void
    private var timer: Timer?

    /// `nextDeadline` mirrors the tracker's for tests to assert on
    /// without a real clock.
    var nextDeadline: Date? { tracker.nextDeadline }

    init(
        threshold: TimeInterval = 10,
        timerEnabled: Bool = true,
        deliver: @escaping (AgentEvent) -> Void
    ) {
        tracker = CursorApprovalPendingTracker(threshold: threshold)
        self.timerEnabled = timerEnabled
        self.deliver = deliver
        super.init()
    }

    func observe(_ event: AgentEvent, now: Date = Date()) {
        reschedule(for: tracker.handle(event, now: now))
    }

    /// Delivers every pending approval whose deadline is at or before
    /// `now`. The real timer calls this at each deadline; tests call it
    /// directly to stay independent of wall-clock time.
    func fireDue(now: Date = Date()) {
        let fired = tracker.fireDue(now: now)
        reschedule(for: tracker.nextDeadline)
        for approval in fired {
            deliver(
                AgentHookEventAdapter.pendingApprovalEvent(
                    runID: approval.runID,
                    command: approval.command,
                    sessionID: approval.sessionID,
                    surfaceID: approval.surfaceID,
                    occurredAt: now
                )
            )
        }
    }

    @objc private func timerDidFire(_ timer: Timer) {
        fireDue(now: Date())
    }

    private func reschedule(for deadline: Date?) {
        timer?.invalidate()
        timer = nil
        guard timerEnabled, let deadline else { return }
        let timer = Timer(
            fireAt: deadline,
            interval: 0,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
