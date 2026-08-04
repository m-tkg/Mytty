import Foundation
import MyTTYCore

/// Owns the wall-clock timer behind `NativeAgentRunEstimator`, the same
/// split `CursorApprovalCoordinator` uses for `CursorApprovalPendingTracker`:
/// the estimator is a pure state machine, this class is the only thing that
/// touches an actual `Timer`. `AppDelegate` forwards every foreground
/// provider transition (`AgentStatusPollingCoordinator`), every OSC 133
/// command-end (`TerminalWindowController`), and every observed
/// `AgentEvent` (`receiveAgentEvent`) here, and delivers whatever comes back
/// through `deliver` -- the same `AppDelegate.deliverSyntheticAgentEvent`
/// path `CursorApprovalCoordinator` uses, so focused-pane auto-ack, the
/// phone push, and banner suppression all apply unchanged.
@MainActor
final class NativeAgentRunCoordinator: NSObject {
    private let estimator: NativeAgentRunEstimator
    private let timerEnabled: Bool
    private let deliver: (AgentEvent) -> Void
    private var timer: Timer?

    /// Mirrors the estimator's for tests to assert on without a real clock.
    var nextDeadline: Date? { estimator.nextDeadline }

    init(
        startGrace: TimeInterval = 3,
        timerEnabled: Bool = true,
        deliver: @escaping (AgentEvent) -> Void
    ) {
        estimator = NativeAgentRunEstimator(startGrace: startGrace)
        self.timerEnabled = timerEnabled
        self.deliver = deliver
        super.init()
    }

    func providerChanged(
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider?,
        processID: pid_t?,
        suppressedProviders: Set<AgentProvider>,
        now: Date = Date()
    ) {
        let events = estimator.providerChanged(
            surfaceID: surfaceID,
            provider: provider,
            processID: processID,
            suppressedProviders: suppressedProviders,
            now: now
        )
        deliverAndReschedule(events)
    }

    func commandFinished(
        surfaceID: TerminalSurfaceID,
        exitCode: Int?,
        now: Date = Date()
    ) {
        let events = estimator.commandFinished(
            surfaceID: surfaceID,
            exitCode: exitCode,
            now: now
        )
        deliverAndReschedule(events)
    }

    func observe(_ event: AgentEvent) {
        estimator.observeRealEvent(event)
        reschedule(for: estimator.nextDeadline)
    }

    /// Delivers every epoch whose start grace has elapsed at or before
    /// `now`. The real timer calls this at each deadline; tests call it
    /// directly to stay independent of wall-clock time.
    func fireDue(now: Date = Date()) {
        deliverAndReschedule(estimator.fireDue(now: now))
    }

    @objc private func timerDidFire(_ timer: Timer) {
        fireDue(now: Date())
    }

    private func deliverAndReschedule(_ events: [AgentEvent]) {
        reschedule(for: estimator.nextDeadline)
        for event in events {
            deliver(event)
        }
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
