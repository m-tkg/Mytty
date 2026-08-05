import Foundation

/// Pure planning for `agent spawn --worktree <branch>`: given the base
/// repository root and the requested branch, works out the worktree's
/// target path and — once the caller (`AgentWorktreePreparer` in
/// `MyTTYApp`) has consulted the repo's registered worktrees, the
/// filesystem, and existing refs — exactly what to do about it. No
/// `Process` or `FileManager` calls live here, which is what makes path
/// derivation, porcelain parsing, and argv construction unit-testable
/// without a real git binary; `AgentWorktreePreparer` owns the actual git
/// execution and calls into this type to decide what to run.
public enum AgentWorktreePlan {
    /// `<repoRoot parent>/<repoRoot lastPathComponent>-worktrees/<sanitized
    /// branch>` — a sibling of the repo root, never inside it, so an
    /// orchestrator's worktrees don't pollute `git status` in the main
    /// checkout. `/` in the branch becomes `-` for the path component only
    /// (`feat/x` -> directory `feat-x`); the branch itself is passed to git
    /// unmodified.
    public static func worktreePath(
        repositoryRoot: URL,
        branch: String
    ) -> URL {
        let sanitizedBranch = branch.replacingOccurrences(of: "/", with: "-")
        let worktreesDirectoryName =
            "\(repositoryRoot.lastPathComponent)-worktrees"
        return repositoryRoot
            .deletingLastPathComponent()
            .appendingPathComponent(worktreesDirectoryName, isDirectory: true)
            .appendingPathComponent(sanitizedBranch, isDirectory: true)
    }

    /// Parses `git worktree list --porcelain` output into the set of paths
    /// already registered as worktrees of the repo. Porcelain format: each
    /// entry starts with a `worktree <path>` line, followed by `HEAD
    /// <sha>` and either `branch <ref>`, `bare`, or `detached`, with a
    /// blank line separating entries. Only the `worktree` lines matter for
    /// reuse detection — which branch a registered worktree currently has
    /// checked out is deliberately irrelevant (a target path that's
    /// already registered is reused as-is, regardless of its branch).
    public static func registeredWorktreePaths(
        porcelainOutput: String
    ) -> Set<String> {
        var paths: Set<String> = []
        for line in porcelainOutput.split(
            separator: "\n",
            omittingEmptySubsequences: true
        ) {
            guard line.hasPrefix("worktree ") else { continue }
            let path = line
                .dropFirst("worktree ".count)
                .trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            paths.insert(path)
        }
        return paths
    }

    public enum Decision: Equatable, Sendable {
        /// The target path is already a registered worktree of the repo —
        /// reuse it as-is (idempotent respawn), regardless of which branch
        /// it currently has checked out.
        case reuse
        /// The target path exists on disk but isn't a registered worktree
        /// — `AgentWorktreePreparer` maps this to the
        /// `worktree-create-failed` failure code rather than clobbering
        /// whatever is there.
        case pathExists
        /// Run `git -C <repoRoot> worktree add <argv...>` (the executable
        /// and `-C <repoRoot>` are not included — `AgentWorktreePreparer`
        /// prepends those) to create the worktree.
        case create(argv: [String])
    }

    /// Decides what to do once the caller already knows whether the target
    /// path is registered, exists on disk, and whether `branch` already
    /// exists as a local branch. Pure decision table — no I/O, no ordering
    /// requirement between the three inputs beyond what's documented on
    /// `Decision`.
    public static func decide(
        branch: String,
        worktreePath: URL,
        registeredWorktreePaths: Set<String>,
        pathExistsOnDisk: Bool,
        branchExists: Bool
    ) -> Decision {
        let target = worktreePath.standardizedFileURL.path
        let isRegistered = registeredWorktreePaths.contains {
            URL(fileURLWithPath: $0).standardizedFileURL.path == target
        }
        if isRegistered {
            return .reuse
        }
        if pathExistsOnDisk {
            return .pathExists
        }
        let path = worktreePath.path
        if branchExists {
            return .create(argv: ["worktree", "add", path, branch])
        }
        return .create(argv: ["worktree", "add", "-b", branch, path])
    }
}
