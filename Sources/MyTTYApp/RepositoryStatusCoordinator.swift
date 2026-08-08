import AppKit
import MyTTYCore

/// Owns the 2s "which git repository / GitHub page does each visible pane's
/// working directory belong to" poll: the `GitHubRepositoryLoader`, the timer,
/// and the request bookkeeping that discards a load once its directory
/// stopped being requested before it completed. Extracted from
/// `TerminalWindowController.refreshRepositoryIfNeeded` /
/// `startRepositoryObservation` / `clearRepositoryStatus` — the 2s
/// interval/0.25s tolerance and the `.common` run loop mode are unchanged,
/// but each tick only re-runs `git` for a directory when a cheap
/// `GitRepositoryFingerprint` of `HEAD`/`config` shows the answer could
/// actually have changed (or nothing has loaded for it yet); a directory with
/// no `.git` at all skips `git` entirely. `force: true` still bypasses that
/// gating for external callers.
/// Its shape mirrors `AgentUsagePollingCoordinator` deliberately (same
/// request-superseding pattern against a different data source) without
/// sharing a base class.
///
/// State is kept per directory rather than for a single focused one, so a
/// tab split across several repositories can show each pane's own branch.
/// The steady-state `git` cost is unchanged: the fingerprint gate means the
/// number of `git` invocations tracks how many repositories actually changed,
/// not how many panes are open.
///
/// `TerminalWindowController` owns this coordinator and supplies the visible
/// panes' working directories via a closure (querying `WindowSession`, which
/// stays controller-private) rather than this type reaching into it directly.
@MainActor
final class RepositoryStatusCoordinator: NSObject {
    /// What is known about one directory. An entry exists as soon as the
    /// directory is polled — including for a directory that is not a git
    /// working tree at all, so the transition out of `.notARepository`
    /// (a `git init`) is picked up without ever spawning `git` for it.
    private struct Entry {
        /// The fingerprint as of the last load that was actually started
        /// for this directory. Deliberately not refreshed while a load is
        /// in flight, so a metadata change mid-load isn't lost: the next
        /// tick still compares against this (now stale) value once the
        /// in-flight load's gate lets it through.
        var fingerprint: GitRepositoryFingerprint
        var status: GitHubRepositoryStatus?
        var hasCompletedLoad: Bool
    }

    /// How many fresh loads may start in a single tick. One load runs up to
    /// three `git` processes, so opening a tab full of panes across distinct
    /// repositories would otherwise spawn a burst of them at once; the rest
    /// are picked up by the following ticks, focused pane first.
    private static let maxLoadsPerTick = 4
    /// Upper bound on how many distinct directories are tracked at all, so a
    /// pathological pane count can't turn each tick into a fingerprint storm.
    private static let maxTrackedDirectories = 16

    private var entries: [URL: Entry] = [:]
    private var inFlight: [URL: (id: UUID, task: Task<Void, Never>)] = [:]

    private let loader: GitHubRepositoryLoader
    /// Computes the gating fingerprint for a directory; overridable in
    /// tests so they can drive the gating logic without a real `.git` on
    /// disk. Defaults to the real filesystem-backed implementation.
    private let fingerprintProvider: (URL) -> GitRepositoryFingerprint
    private var timer: Timer?

    /// The directories to keep status for, most important first — the
    /// controller puts the focused pane's directory at the front so it wins
    /// both the per-tick load budget and the tracking cap.
    private let directories: () -> [URL]
    /// Fired whenever a directory's status changes (including being
    /// cleared) — the controller uses this to refresh the status bars.
    private let onStatusChanged: () -> Void

    init(
        loader: GitHubRepositoryLoader = GitHubRepositoryLoader(),
        fingerprint: @escaping (URL) -> GitRepositoryFingerprint = GitRepositoryFingerprint.compute,
        directories: @escaping () -> [URL],
        onStatusChanged: @escaping () -> Void
    ) {
        self.loader = loader
        self.fingerprintProvider = fingerprint
        self.directories = directories
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
        for (_, request) in inFlight {
            request.task.cancel()
        }
        inFlight.removeAll()
    }

    @objc private func timerDidFire(_ timer: Timer) {
        // No `force`: the fingerprint gating inside `refreshIfNeeded`
        // decides whether this tick actually needs to spawn `git`.
        refreshIfNeeded()
    }

    /// Status for `directory`, or `nil` if nothing has loaded for it
    /// (including while a load for it is in flight).
    func status(for directory: URL?) -> GitHubRepositoryStatus? {
        guard let directory else { return nil }
        return entries[directory.standardizedFileURL]?.status
    }

    /// Directories with a completed load, for tests.
    var loadedDirectories: Set<URL> {
        Set(entries.filter { $0.value.hasCompletedLoad }.keys)
    }

    func refreshIfNeeded(force: Bool = false) {
        let requested = requestedDirectories()
        // A single fire covers everything this tick invalidated: dropping a
        // directory that is no longer shown, and clearing the display for a
        // directory whose first load is only starting now. Matches the
        // single-directory behavior this generalizes, where re-focusing
        // fired once no matter how many pieces of state it reset.
        var didClear = false

        for (directory, entry) in entries where !requested.contains(directory) {
            // Only an entry that was showing something — or that has a load
            // running whose result someone is waiting for — is worth a
            // redraw when it goes away.
            if entry.status != nil || inFlight[directory] != nil {
                didClear = true
            }
            entries[directory] = nil
            cancelLoad(for: directory)
        }

        var started = 0
        for directory in requested {
            let fingerprint = fingerprintProvider(directory)
            guard fingerprint != .notARepository else {
                if clearForNonRepository(directory, fingerprint: fingerprint) {
                    didClear = true
                }
                continue
            }

            let entry = entries[directory]
            let hasCompletedLoad = entry?.hasCompletedLoad ?? false
            let fingerprintChanged = entry?.fingerprint != fingerprint
            guard force || !hasCompletedLoad || fingerprintChanged else { continue }
            // Never pile a second request on a directory already loading,
            // not even when forced.
            guard inFlight[directory] == nil else { continue }
            guard started < Self.maxLoadsPerTick else { continue }
            started += 1

            entries[directory] = Entry(
                fingerprint: fingerprint,
                status: entry?.status,
                hasCompletedLoad: hasCompletedLoad
            )
            if !hasCompletedLoad {
                // Nothing trustworthy is on screen for this directory yet;
                // drop whatever stale value was there before loading.
                entries[directory]?.status = nil
                didClear = true
            }
            startLoad(for: directory)
        }

        if didClear {
            onStatusChanged()
        }
    }

    /// Deduplicated, normalized and capped request list, order preserved so
    /// the focused pane's directory keeps priority.
    private func requestedDirectories() -> [URL] {
        var seen: Set<URL> = []
        var result: [URL] = []
        for directory in directories() {
            let normalized = directory.standardizedFileURL
            guard seen.insert(normalized).inserted else { continue }
            result.append(normalized)
            if result.count == Self.maxTrackedDirectories { break }
        }
        return result
    }

    private func startLoad(for directory: URL) {
        let newRequestID = UUID()
        let loader = loader
        let task = Task { [weak self] in
            let status = await loader.load(from: directory)
            guard !Task.isCancelled,
                  let self,
                  inFlight[directory]?.id == newRequestID
            else { return }
            inFlight[directory] = nil
            entries[directory]?.status = status
            entries[directory]?.hasCompletedLoad = true
            onStatusChanged()
        }
        inFlight[directory] = (id: newRequestID, task: task)
    }

    private func cancelLoad(for directory: URL) {
        inFlight[directory]?.task.cancel()
        inFlight[directory] = nil
    }

    /// `directory` is shown but isn't a git working tree at all: track it
    /// (so a later `git init` is picked up via the fingerprint transition
    /// out of `.notARepository`) without ever spawning `git` for it.
    /// Returns whether that dropped something that was on screen.
    private func clearForNonRepository(
        _ directory: URL,
        fingerprint: GitRepositoryFingerprint
    ) -> Bool {
        let hadStatus = entries[directory]?.status != nil
        let hadLoad = inFlight[directory] != nil
        cancelLoad(for: directory)
        entries[directory] = Entry(
            fingerprint: fingerprint,
            status: nil,
            hasCompletedLoad: false
        )
        return hadStatus || hadLoad
    }
}
