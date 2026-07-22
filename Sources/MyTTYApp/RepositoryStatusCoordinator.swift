import AppKit
import MyTTYCore

/// Owns the 2s "which GitHub repository does the focused pane's working
/// directory belong to" poll: the `GitHubRepositoryLoader`, the timer, and
/// the request-ID bookkeeping that discards a load once a different
/// directory became focused before it completed. Extracted from
/// `TerminalWindowController.refreshRepositoryIfNeeded` /
/// `startRepositoryObservation` / `clearRepositoryStatus` — the 2s
/// interval/0.25s tolerance and the `.common` run loop mode are unchanged,
/// but each tick now only re-runs `git` when a cheap
/// `GitRepositoryFingerprint` of `HEAD`/`config` shows the answer could
/// actually have changed (or the focused directory changed, or nothing has
/// loaded for it yet); a directory with no `.git` at all skips `git`
/// entirely. `force: true` still bypasses that gating for external callers.
/// Its shape mirrors `AgentUsagePollingCoordinator` deliberately (same
/// request-superseding pattern against a different data source) without
/// sharing a base class.
///
/// `TerminalWindowController` owns this coordinator and supplies the
/// focused pane's working directory via a closure (querying
/// `WindowSession`, which stays controller-private) rather than this type
/// reaching into it directly.
@MainActor
final class RepositoryStatusCoordinator: NSObject {
    private(set) var loadedDirectory: URL?
    private(set) var loadedStatus: GitHubRepositoryStatus?

    private let loader: GitHubRepositoryLoader
    /// Computes the gating fingerprint for a directory; overridable in
    /// tests so they can drive the gating logic without a real `.git` on
    /// disk. Defaults to the real filesystem-backed implementation.
    private let fingerprintProvider: (URL) -> GitRepositoryFingerprint
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var requestedDirectory: URL?
    /// The fingerprint as of the last load that was actually started for
    /// `requestedDirectory`. Deliberately not refreshed while a load is
    /// in flight, so a metadata change mid-load isn't lost: the next tick
    /// still compares against this (now stale) value once the in-flight
    /// load's directory/fingerprint gate lets it through.
    private var requestedFingerprint: GitRepositoryFingerprint?

    private let focusedDirectory: () -> URL?
    /// Fired whenever the loaded directory/status changes (including being
    /// cleared) — the controller uses this to refresh the status bar.
    private let onStatusChanged: () -> Void

    init(
        loader: GitHubRepositoryLoader = GitHubRepositoryLoader(),
        fingerprint: @escaping (URL) -> GitRepositoryFingerprint = GitRepositoryFingerprint.compute,
        focusedDirectory: @escaping () -> URL?,
        onStatusChanged: @escaping () -> Void
    ) {
        self.loader = loader
        self.fingerprintProvider = fingerprint
        self.focusedDirectory = focusedDirectory
        self.onStatusChanged = onStatusChanged
        super.init()
    }

    func start() {
        let timer = Timer(
            timeInterval: 2,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshIfNeeded(force: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }

    @objc private func timerDidFire(_ timer: Timer) {
        // No `force`: the fingerprint gating inside `refreshIfNeeded`
        // decides whether this tick actually needs to spawn `git`.
        refreshIfNeeded()
    }

    /// Status for `directory`, or `nil` if it doesn't match what's
    /// currently loaded (including while a load for it is in flight).
    func status(for directory: URL?) -> GitHubRepositoryStatus? {
        guard let directory, directory == loadedDirectory else { return nil }
        return loadedStatus
    }

    func refreshIfNeeded(force: Bool = false) {
        guard let directory = focusedDirectory() else {
            clear()
            return
        }

        let fingerprint = fingerprintProvider(directory)
        guard fingerprint != .notARepository else {
            clearForNonRepository(directory, fingerprint: fingerprint)
            return
        }

        let directoryChanged = requestedDirectory != directory
        // `loadedDirectory != directory` also covers "a load for this
        // directory was requested but never completed" (e.g. it was
        // cancelled by an earlier directory change and focus has since
        // returned) — distinct from a completed load whose result was
        // legitimately "no GitHub remote" (`loadedStatus == nil` but
        // `loadedDirectory == directory`), which must not re-trigger.
        let noCompletedLoad = loadedDirectory != directory
        let fingerprintChanged = requestedFingerprint != fingerprint
        guard force || directoryChanged || noCompletedLoad || fingerprintChanged else { return }
        guard task == nil || directoryChanged else { return }

        task?.cancel()
        requestedDirectory = directory
        requestedFingerprint = fingerprint
        if loadedDirectory != directory {
            loadedDirectory = nil
            loadedStatus = nil
            onStatusChanged()
        }
        let newRequestID = UUID()
        requestID = newRequestID
        let loader = loader
        task = Task { [weak self] in
            let status = await loader.load(from: directory)
            guard !Task.isCancelled,
                  let self,
                  requestID == newRequestID,
                  requestedDirectory == directory
            else { return }
            loadedDirectory = directory
            loadedStatus = status
            task = nil
            onStatusChanged()
        }
    }

    private func clear() {
        guard requestedDirectory != nil
                || requestedFingerprint != nil
                || loadedDirectory != nil
                || loadedStatus != nil
        else { return }
        task?.cancel()
        task = nil
        requestID = nil
        requestedDirectory = nil
        requestedFingerprint = nil
        loadedDirectory = nil
        loadedStatus = nil
        onStatusChanged()
    }

    /// `directory` is focused but isn't a git working tree at all: track it
    /// (so a later `git init` is picked up via the fingerprint transition
    /// out of `.notARepository`) without ever spawning `git` for it.
    private func clearForNonRepository(_ directory: URL, fingerprint: GitRepositoryFingerprint) {
        task?.cancel()
        task = nil
        requestID = nil
        requestedDirectory = directory
        requestedFingerprint = fingerprint
        guard loadedDirectory != nil || loadedStatus != nil else { return }
        loadedDirectory = nil
        loadedStatus = nil
        onStatusChanged()
    }
}
