import AppKit
import MyTTYCore

/// Owns the 2s "which GitHub repository does the focused pane's working
/// directory belong to" poll: the `GitHubRepositoryLoader`, the timer, and
/// the request-ID bookkeeping that discards a load once a different
/// directory became focused before it completed. Extracted from
/// `TerminalWindowController.refreshRepositoryIfNeeded` /
/// `startRepositoryObservation` / `clearRepositoryStatus` verbatim — the 2s
/// interval/0.25s tolerance, the `.common` run loop mode, and the
/// directory-changed/force gating are unchanged. Its shape mirrors
/// `AgentUsagePollingCoordinator` deliberately (same request-superseding
/// pattern against a different data source) without sharing a base class.
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
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var requestedDirectory: URL?

    private let focusedDirectory: () -> URL?
    /// Fired whenever the loaded directory/status changes (including being
    /// cleared) — the controller uses this to refresh the status bar.
    private let onStatusChanged: () -> Void

    init(
        loader: GitHubRepositoryLoader = GitHubRepositoryLoader(),
        focusedDirectory: @escaping () -> URL?,
        onStatusChanged: @escaping () -> Void
    ) {
        self.loader = loader
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
        refreshIfNeeded(force: true)
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
        let directoryChanged = requestedDirectory != directory
        guard directoryChanged || force else { return }
        guard task == nil || directoryChanged else { return }

        task?.cancel()
        requestedDirectory = directory
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
                || loadedDirectory != nil
                || loadedStatus != nil
        else { return }
        task?.cancel()
        task = nil
        requestID = nil
        requestedDirectory = nil
        loadedDirectory = nil
        loadedStatus = nil
        onStatusChanged()
    }
}
