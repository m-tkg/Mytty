import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent worktree planning")
struct AgentWorktreePlanTests {
    // MARK: - worktreePath

    @Test("derives a sibling -worktrees directory from the repo root")
    func derivesSiblingDirectory() {
        let repositoryRoot = URL(fileURLWithPath: "/Users/dev/mytty")
        let path = AgentWorktreePlan.worktreePath(
            repositoryRoot: repositoryRoot,
            branch: "feature-a"
        )
        #expect(path.path == "/Users/dev/mytty-worktrees/feature-a")
    }

    @Test("sanitizes a slash in the branch to a hyphen in the path component")
    func sanitizesSlashInBranch() {
        let repositoryRoot = URL(fileURLWithPath: "/Users/dev/mytty")
        let path = AgentWorktreePlan.worktreePath(
            repositoryRoot: repositoryRoot,
            branch: "feat/x"
        )
        #expect(path.path == "/Users/dev/mytty-worktrees/feat-x")
    }

    @Test("sanitizes every slash in a multi-segment branch")
    func sanitizesEverySlash() {
        let repositoryRoot = URL(fileURLWithPath: "/Users/dev/mytty")
        let path = AgentWorktreePlan.worktreePath(
            repositoryRoot: repositoryRoot,
            branch: "feat/x/y"
        )
        #expect(path.path == "/Users/dev/mytty-worktrees/feat-x-y")
    }

    // MARK: - registeredWorktreePaths

    @Test("parses every worktree line out of porcelain output")
    func parsesPorcelainWorktreeLines() {
        let porcelain = """
        worktree /Users/dev/mytty
        HEAD abc123
        branch refs/heads/main

        worktree /Users/dev/mytty-worktrees/feat-a
        HEAD def456
        branch refs/heads/feat/a

        worktree /Users/dev/mytty-worktrees/detached
        HEAD 789abc
        detached

        """
        let paths = AgentWorktreePlan.registeredWorktreePaths(
            porcelainOutput: porcelain
        )
        #expect(paths == [
            "/Users/dev/mytty",
            "/Users/dev/mytty-worktrees/feat-a",
            "/Users/dev/mytty-worktrees/detached",
        ])
    }

    @Test("returns an empty set for empty porcelain output")
    func parsesEmptyPorcelainOutput() {
        #expect(AgentWorktreePlan.registeredWorktreePaths(
            porcelainOutput: ""
        ).isEmpty)
    }

    @Test("ignores non-worktree porcelain lines")
    func ignoresNonWorktreeLines() {
        let porcelain = "HEAD abc123\nbranch refs/heads/main\n\n"
        #expect(AgentWorktreePlan.registeredWorktreePaths(
            porcelainOutput: porcelain
        ).isEmpty)
    }

    // MARK: - decide

    @Test("reuses a target path that's already registered, regardless of branch")
    func reusesRegisteredPath() {
        let worktreePath = URL(
            fileURLWithPath: "/Users/dev/mytty-worktrees/feat-a"
        )
        let decision = AgentWorktreePlan.decide(
            branch: "feat/a",
            worktreePath: worktreePath,
            registeredWorktreePaths: [
                "/Users/dev/mytty-worktrees/feat-a",
            ],
            pathExistsOnDisk: true,
            branchExists: true
        )
        #expect(decision == .reuse)
    }

    @Test("reuses a registered path even when it holds a different branch")
    func reusesRegisteredPathRegardlessOfBranch() {
        let worktreePath = URL(
            fileURLWithPath: "/Users/dev/mytty-worktrees/feat-a"
        )
        let decision = AgentWorktreePlan.decide(
            branch: "feat/a",
            worktreePath: worktreePath,
            registeredWorktreePaths: [
                "/Users/dev/mytty-worktrees/feat-a",
            ],
            pathExistsOnDisk: true,
            branchExists: false
        )
        #expect(decision == .reuse)
    }

    @Test("fails when the target path exists on disk but isn't registered")
    func failsWhenPathExistsUnregistered() {
        let worktreePath = URL(
            fileURLWithPath: "/Users/dev/mytty-worktrees/feat-a"
        )
        let decision = AgentWorktreePlan.decide(
            branch: "feat/a",
            worktreePath: worktreePath,
            registeredWorktreePaths: [],
            pathExistsOnDisk: true,
            branchExists: false
        )
        #expect(decision == .pathExists)
    }

    @Test("builds a plain worktree add argv for an existing branch")
    func buildsArgvForExistingBranch() {
        let worktreePath = URL(
            fileURLWithPath: "/Users/dev/mytty-worktrees/feat-a"
        )
        let decision = AgentWorktreePlan.decide(
            branch: "feat/a",
            worktreePath: worktreePath,
            registeredWorktreePaths: [],
            pathExistsOnDisk: false,
            branchExists: true
        )
        #expect(decision == .create(argv: [
            "worktree", "add", "/Users/dev/mytty-worktrees/feat-a", "feat/a",
        ]))
    }

    @Test("builds a -b worktree add argv for a branch that doesn't exist yet")
    func buildsArgvForNewBranch() {
        let worktreePath = URL(
            fileURLWithPath: "/Users/dev/mytty-worktrees/feat-a"
        )
        let decision = AgentWorktreePlan.decide(
            branch: "feat/a",
            worktreePath: worktreePath,
            registeredWorktreePaths: [],
            pathExistsOnDisk: false,
            branchExists: false
        )
        #expect(decision == .create(argv: [
            "worktree", "add", "-b", "feat/a",
            "/Users/dev/mytty-worktrees/feat-a",
        ]))
    }
}
