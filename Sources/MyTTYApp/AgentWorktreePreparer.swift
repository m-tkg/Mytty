import Foundation
import MyTTYCore

/// Something that can create or reuse a git worktree for `agent spawn
/// --worktree <branch>`. `AgentJobCoordinator` depends on this protocol
/// rather than the concrete `AgentWorktreePreparer`, so its spawn logic can
/// be exercised in tests with a stub that never shells out to git — see
/// `AgentJobCoordinator.resolveWorktreeWorkingDirectory`.
protocol AgentWorktreePreparing: Sendable {
    /// `directory` is the base repository's resolved spawn cwd — the
    /// `--cwd` value if given, otherwise the anchor pane's working
    /// directory — before `--worktree` is applied. Returns the worktree's
    /// absolute path on success, or `not-a-git-repository` /
    /// `worktree-create-failed` on failure; see `docs/reference/mytty-ctl.md`'s
    /// `agent spawn --worktree` section for the exact semantics.
    func prepareWorktree(
        forDirectory directory: URL,
        branch: String
    ) async -> Result<URL, AgentControlFailure>
}

/// Real `git` execution behind `AgentWorktreePreparing`. Every invocation
/// uses `Process` with an argument array (never a shell string), runs off
/// the main actor via `Task.detached`, and is capped at `commandTimeout` so
/// a hung git process can't wedge a spawn forever. Pure decision-making
/// (path derivation, porcelain parsing, argv construction) is delegated to
/// `AgentWorktreePlan` (MyTTYCore) so that logic stays unit-testable
/// without a real git binary — this type only does the I/O
/// `AgentWorktreePlan` can't.
struct AgentWorktreePreparer: AgentWorktreePreparing {
    private static let executable = URL(fileURLWithPath: "/usr/bin/git")

    private let commandTimeout: TimeInterval

    init(commandTimeout: TimeInterval = 30) {
        self.commandTimeout = commandTimeout
    }

    func prepareWorktree(
        forDirectory directory: URL,
        branch: String
    ) async -> Result<URL, AgentControlFailure> {
        guard let topLevel = await run([
            "-C", directory.path, "rev-parse", "--show-toplevel",
        ]), topLevel.exitCode == 0,
            let repositoryRootPath = topLevel.standardOutput?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !repositoryRootPath.isEmpty
        else {
            return .failure(AgentControlFailure("not-a-git-repository"))
        }
        let repositoryRoot = URL(
            fileURLWithPath: repositoryRootPath,
            isDirectory: true
        )

        let worktreePath = AgentWorktreePlan.worktreePath(
            repositoryRoot: repositoryRoot,
            branch: branch
        )

        let listResult = await run([
            "-C", repositoryRoot.path, "worktree", "list", "--porcelain",
        ])
        let registeredPaths = AgentWorktreePlan.registeredWorktreePaths(
            porcelainOutput: listResult?.standardOutput ?? ""
        )

        var isDirectory: ObjCBool = false
        let pathExists = FileManager.default.fileExists(
            atPath: worktreePath.path,
            isDirectory: &isDirectory
        )

        let branchCheck = await run([
            "-C", repositoryRoot.path, "rev-parse", "--verify", "--quiet",
            "refs/heads/\(branch)",
        ])
        let branchExists = branchCheck?.exitCode == 0

        switch AgentWorktreePlan.decide(
            branch: branch,
            worktreePath: worktreePath,
            registeredWorktreePaths: registeredPaths,
            pathExistsOnDisk: pathExists,
            branchExists: branchExists
        ) {
        case .reuse:
            return .success(worktreePath)
        case .pathExists:
            return .failure(AgentControlFailure("worktree-create-failed"))
        case let .create(argv):
            let created = await run(["-C", repositoryRoot.path] + argv)
            guard created?.exitCode == 0 else {
                return .failure(AgentControlFailure("worktree-create-failed"))
            }
            return .success(worktreePath)
        }
    }

    // MARK: - git process execution

    private struct GitInvocationResult {
        let exitCode: Int32
        let standardOutput: String?
    }

    private func run(_ arguments: [String]) async -> GitInvocationResult? {
        let timeout = commandTimeout
        return await Task.detached(priority: .utility) {
            Self.runSynchronously(arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runSynchronously(
        arguments: [String],
        timeout: TimeInterval
    ) -> GitInvocationResult? {
        let process = Process()
        let output = Pipe()
        let buffer = AgentWorktreeOutputBuffer()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 0.5)
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        output.fileHandleForReading.readabilityHandler = nil
        buffer.append(output.fileHandleForReading.availableData)
        return GitInvocationResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: buffer.data, encoding: .utf8)
        )
    }
}

private final class AgentWorktreeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data { lock.withLock { storage } }

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }
}
