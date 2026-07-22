import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// Characterization tests for `RepositoryStatusCoordinator`: pin down the
/// behavior extracted from `TerminalWindowController.refreshRepositoryIfNeeded`
/// / `clearRepositoryStatus` — only refetching when the focused directory
/// changes (or `force` is set), never starting a second load for a
/// directory that already has one in flight even when forced, discarding a
/// load whose directory is no longer focused by the time it completes, and
/// clearing state once no directory is focused.
///
/// A `GatedGitCommandRunner` stands in for the real `git` process runner so
/// tests can suspend a load mid-flight (per directory) and control exactly
/// when it resolves, mirroring `AgentUsagePollingCoordinatorTests`' gated
/// loader for the analogous race in the usage coordinator.
@Suite("Repository status coordinator")
struct RepositoryStatusCoordinatorTests {
    private let directoryA = URL(fileURLWithPath: "/repo-a", isDirectory: true)
    private let directoryB = URL(fileURLWithPath: "/repo-b", isDirectory: true)

    private func loader(_ runner: GatedGitCommandRunner) -> GitHubRepositoryLoader {
        GitHubRepositoryLoader(runner: runner)
    }

    /// Same fingerprint for every directory, so these characterization
    /// tests exercise only the pre-existing directory-changed/force/
    /// in-flight gating, unaffected by `GitRepositoryFingerprint`
    /// (covered separately below and in `GitRepositoryFingerprintTests`).
    private func neutralFingerprint(_ directory: URL) -> GitRepositoryFingerprint {
        .repository(head: .absent, config: .absent)
    }

    @MainActor
    private func settle(until condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func pause() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("loads status for the focused directory")
    @MainActor
    func loadsStatusForDirectory() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        var changeCount = 0
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { self.directoryA },
            onStatusChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { coordinator.status(for: self.directoryA) != nil }

        #expect(coordinator.status(for: directoryA)?.branchName == "main")
        // Fires once to clear any stale display before the load starts,
        // and once more with the fresh result — matching the original
        // `refreshRepositoryIfNeeded`'s two `updateStatusBar()` call sites.
        #expect(changeCount == 2)
        #expect(await runner.callCount(for: directoryA) > 0)
    }

    @Test("does nothing when no pane has a focused directory")
    @MainActor
    func noDirectoryDoesNothing() async {
        let runner = GatedGitCommandRunner()
        var changeCount = 0
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { nil },
            onStatusChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded(force: true)
        await pause()

        #expect(coordinator.status(for: nil) == nil)
        #expect(changeCount == 0)
    }

    @Test("skips refetching the same directory without force")
    @MainActor
    func sameDirectorySkipsWithoutForce() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { self.directoryA },
            onStatusChanged: {}
        )

        coordinator.refreshIfNeeded()
        await settle { coordinator.status(for: self.directoryA) != nil }
        coordinator.refreshIfNeeded()
        await pause()

        #expect(await runner.callCount(for: directoryA) == 1)
    }

    @Test("force does not restart a load already in flight for the same directory")
    @MainActor
    func forceDoesNotDuplicateInFlightLoad() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        await runner.hold(directoryA)
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { self.directoryA },
            onStatusChanged: {}
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { await runner.callCount(for: self.directoryA) > 0 }
        coordinator.refreshIfNeeded(force: true)
        await pause()

        // Still only the one in-flight call; force doesn't pile on a
        // second request for a directory already being loaded.
        #expect(await runner.callCount(for: directoryA) == 1)

        await runner.release(directoryA)
        await settle { coordinator.status(for: self.directoryA) != nil }
        #expect(coordinator.status(for: directoryA)?.branchName == "main")
    }

    @Test("force reloads the same directory once its prior load finished")
    @MainActor
    func forceReloadsAfterPriorLoadFinished() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { self.directoryA },
            onStatusChanged: {}
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { coordinator.status(for: self.directoryA) != nil }
        coordinator.refreshIfNeeded(force: true)
        await settle { await runner.callCount(for: self.directoryA) == 2 }

        #expect(await runner.callCount(for: directoryA) == 2)
    }

    @Test("discards a stale load once a different directory becomes focused")
    @MainActor
    func discardsStaleLoadOnDirectoryChange() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        await runner.setStatus(directoryB, branch: "feature")
        await runner.hold(directoryA)
        var focused = directoryA
        var changeCount = 0
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { focused },
            onStatusChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { await runner.callCount(for: self.directoryA) > 0 }
        #expect(coordinator.status(for: directoryA) == nil)

        focused = directoryB
        coordinator.refreshIfNeeded()
        await settle { coordinator.status(for: self.directoryB) != nil }

        #expect(coordinator.status(for: directoryB)?.branchName == "feature")
        // One fire when A's load starts (clearing stale display), one
        // when refocusing to B clears state again, one when B's result
        // lands.
        #expect(changeCount == 3)

        // Releasing the stale directory-A load must not overwrite the
        // result already showing for directory B.
        await runner.release(directoryA)
        await pause()

        #expect(coordinator.status(for: directoryB)?.branchName == "feature")
        #expect(changeCount == 3)
    }

    @Test("losing focus cancels the in-flight load and clears the request")
    @MainActor
    func losingFocusCancelsInFlightLoad() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        await runner.hold(directoryA)
        var focused: URL? = directoryA
        var changeCount = 0
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: neutralFingerprint,
            focusedDirectory: { focused },
            onStatusChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { await runner.callCount(for: self.directoryA) > 0 }

        focused = nil
        coordinator.refreshIfNeeded()
        await runner.release(directoryA)
        await pause()

        #expect(coordinator.status(for: directoryA) == nil)
        // One fire when A's load starts (clearing stale display), one
        // when losing focus clears the request.
        #expect(changeCount == 2)
    }

    @Test("repeated ticks with an unchanged fingerprint do not re-invoke git")
    @MainActor
    func unchangedFingerprintSkipsReload() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: { _ in
                .repository(head: .present(mtime: .distantPast, size: 1), config: .absent)
            },
            focusedDirectory: { self.directoryA },
            onStatusChanged: {}
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { coordinator.status(for: self.directoryA) != nil }
        // Mirrors what `timerDidFire` does every 2s: repeated non-force
        // calls for the same, unchanged directory.
        coordinator.refreshIfNeeded()
        coordinator.refreshIfNeeded()
        coordinator.refreshIfNeeded()
        await pause()

        #expect(await runner.callCount(for: directoryA) == 1)
    }

    @Test("a HEAD rewrite triggers exactly one reload")
    @MainActor
    func headRewriteTriggersOneReload() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        var head = GitRepositoryFingerprint.FileState.present(mtime: .distantPast, size: 1)
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: { _ in .repository(head: head, config: .absent) },
            focusedDirectory: { self.directoryA },
            onStatusChanged: {}
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { coordinator.status(for: self.directoryA) != nil }

        // A commit or branch switch changes HEAD's mtime/size.
        head = .present(mtime: Date(), size: 2)
        coordinator.refreshIfNeeded()
        await settle { await runner.callCount(for: self.directoryA) == 2 }
        coordinator.refreshIfNeeded()
        coordinator.refreshIfNeeded()
        await pause()

        #expect(await runner.callCount(for: directoryA) == 2)
    }

    @Test("a directory with no .git never spawns git")
    @MainActor
    func nonRepositorySkipsGit() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        var changeCount = 0
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: { _ in .notARepository },
            focusedDirectory: { self.directoryA },
            onStatusChanged: { changeCount += 1 }
        )

        coordinator.refreshIfNeeded(force: true)
        coordinator.refreshIfNeeded()
        coordinator.refreshIfNeeded()
        await pause()

        #expect(coordinator.status(for: directoryA) == nil)
        #expect(await runner.callCount(for: directoryA) == 0)
        #expect(changeCount == 0)
    }

    @Test("clears status without spawning git once a loaded directory stops being a repository")
    @MainActor
    func losingRepositoryClearsStatusWithoutSpawningGit() async {
        let runner = GatedGitCommandRunner()
        await runner.setStatus(directoryA, branch: "main")
        var fingerprint: GitRepositoryFingerprint = .repository(head: .absent, config: .absent)
        let coordinator = RepositoryStatusCoordinator(
            loader: loader(runner),
            fingerprint: { _ in fingerprint },
            focusedDirectory: { self.directoryA },
            onStatusChanged: {}
        )

        coordinator.refreshIfNeeded(force: true)
        await settle { coordinator.status(for: self.directoryA) != nil }
        let callsBeforeLosingRepo = await runner.callCount(for: directoryA)

        fingerprint = .notARepository
        coordinator.refreshIfNeeded()
        await pause()

        #expect(coordinator.status(for: directoryA) == nil)
        #expect(await runner.callCount(for: directoryA) == callsBeforeLosingRepo)
    }
}

/// A `GitCommandRunning` fake that resolves `git remote` / `git branch`
/// output for a fixed set of directories, and can suspend the whole
/// `GitHubRepositoryLoader.load` call for a directory until released —
/// `load` issues its first `output` call (`git remote`) before touching
/// anything else, so gating that call is enough to hold the entire load.
private actor GatedGitCommandRunner: GitCommandRunning {
    private var branches: [URL: String] = [:]
    private var callCounts: [URL: Int] = [:]
    private var gatedDirectories: Set<URL> = []
    private var waiting: [URL: [CheckedContinuation<Void, Never>]] = [:]

    func setStatus(_ directory: URL, branch: String) {
        branches[directory] = branch
    }

    func hold(_ directory: URL) {
        gatedDirectories.insert(directory)
    }

    func release(_ directory: URL) {
        gatedDirectories.remove(directory)
        let continuations = waiting[directory] ?? []
        waiting[directory] = nil
        for continuation in continuations {
            continuation.resume()
        }
    }

    func callCount(for directory: URL) -> Int {
        callCounts[directory] ?? 0
    }

    func output(in directory: URL, arguments: [String]) async -> String? {
        if arguments == ["remote"] {
            callCounts[directory, default: 0] += 1
            if gatedDirectories.contains(directory) {
                await withCheckedContinuation { continuation in
                    waiting[directory, default: []].append(continuation)
                }
            }
            return branches[directory] != nil ? "origin\n" : nil
        }
        if arguments == ["remote", "get-url", "origin"] {
            guard let name = branches[directory] else { return nil }
            _ = name
            return "git@github.com:m-tkg/Mytty.git\n"
        }
        if arguments == ["branch", "--show-current"] {
            return branches[directory].map { "\($0)\n" }
        }
        return nil
    }
}
