import Foundation

/// The daemon-side state machine behind `ClamshellHelperXPC`: applies
/// `pmset disablesleep` only when the desired state actually changes and
/// watches the controlling app's process, restoring normal sleep the
/// moment it exits. Pure logic with injected effects so it can be tested
/// without root.
public final class ClamshellHelperCore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "clamshell-helper-core")
    private let setDisableSleep: (Bool) -> Bool
    private let isProcessAlive: (pid_t) -> Bool
    private let pollInterval: TimeInterval

    private var enabled = false
    private var watchedPID: pid_t = 0
    private var watchTimer: DispatchSourceTimer?

    public init(
        pollInterval: TimeInterval = 2,
        setDisableSleep: @escaping (Bool) -> Bool,
        isProcessAlive: @escaping (pid_t) -> Bool = { kill($0, 0) == 0 }
    ) {
        self.pollInterval = pollInterval
        self.setDisableSleep = setDisableSleep
        self.isProcessAlive = isProcessAlive
    }

    /// Applies the requested state; returns false when `pmset` failed
    /// (the previous state is kept in that case so a retry re-runs it).
    public func setKeepAwake(_ requested: Bool, watchedPID pid: pid_t) -> Bool {
        queue.sync {
            if requested {
                guard pid > 0, isProcessAlive(pid) else { return false }
                if !enabled {
                    guard setDisableSleep(true) else { return false }
                    enabled = true
                }
                watchedPID = pid
                startWatchTimerLocked()
                return true
            }
            stopWatchTimerLocked()
            if enabled {
                guard setDisableSleep(false) else { return false }
                enabled = false
            }
            return true
        }
    }

    private func startWatchTimerLocked() {
        guard watchTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval
        )
        timer.setEventHandler { [weak self] in
            self?.watchTickLocked()
        }
        timer.resume()
        watchTimer = timer
    }

    private func stopWatchTimerLocked() {
        watchTimer?.cancel()
        watchTimer = nil
    }

    /// Runs on `queue` via the timer.
    private func watchTickLocked() {
        guard enabled else {
            stopWatchTimerLocked()
            return
        }
        if !isProcessAlive(watchedPID) {
            if setDisableSleep(false) {
                enabled = false
                stopWatchTimerLocked()
            }
            // On failure the timer keeps firing and retries the restore.
        }
    }
}
