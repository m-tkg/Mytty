import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// `AgentJobCoordinator.resolveWorktreeWorkingDirectory` is the pure-ish
/// orchestration step `agent spawn --worktree <branch>` hooks into once the
/// spawn's base cwd is resolved (see `AgentJobCoordinator.swift`'s
/// `spawnAgentAnchorPaneID` handling). It's pulled out as a `static`
/// function specifically so it's testable here without a real
/// `WindowSessionCoordinator`/live pane, which `AgentJobCoordinator`
/// otherwise requires end to end (no test in this suite constructs one —
/// see `ControlServerTests` for why spawn is only exercised through
/// `ControlServerAgentDelegate` stubs instead).
@MainActor
@Suite("Agent job coordinator worktree resolution")
struct AgentJobCoordinatorWorktreeTests {
    @Test("substitutes the worktree path the preparer returns")
    func substitutesWorktreePath() async {
        let worktreeURL = URL(
            fileURLWithPath: "/Users/dev/mytty-worktrees/feat-a"
        )
        let preparer = StubAgentWorktreePreparer(
            result: .success(worktreeURL)
        )
        let result = await AgentJobCoordinator.resolveWorktreeWorkingDirectory(
            baseDirectory: URL(fileURLWithPath: "/Users/dev/mytty"),
            branch: "feat/a",
            preparer: preparer
        )
        #expect(result == .success(worktreeURL))
        #expect(preparer.lastDirectory?.path == "/Users/dev/mytty")
        #expect(preparer.lastBranch == "feat/a")
    }

    @Test("propagates the preparer's failure code unchanged")
    func propagatesPreparerFailure() async {
        let preparer = StubAgentWorktreePreparer(
            result: .failure(AgentControlFailure("worktree-create-failed"))
        )
        let result = await AgentJobCoordinator.resolveWorktreeWorkingDirectory(
            baseDirectory: URL(fileURLWithPath: "/Users/dev/mytty"),
            branch: "feat/a",
            preparer: preparer
        )
        #expect(result == .failure(AgentControlFailure(
            "worktree-create-failed"
        )))
    }

    @Test("propagates not-a-git-repository unchanged")
    func propagatesNotAGitRepositoryFailure() async {
        let preparer = StubAgentWorktreePreparer(
            result: .failure(AgentControlFailure("not-a-git-repository"))
        )
        let result = await AgentJobCoordinator.resolveWorktreeWorkingDirectory(
            baseDirectory: URL(fileURLWithPath: "/Users/dev/mytty"),
            branch: "feat/a",
            preparer: preparer
        )
        #expect(result == .failure(AgentControlFailure(
            "not-a-git-repository"
        )))
    }

    @Test("rejects an invalid branch before ever consulting the preparer")
    func rejectsInvalidBranchWithoutCallingPreparer() async {
        let preparer = StubAgentWorktreePreparer(
            result: .success(URL(fileURLWithPath: "/should/not/be/used"))
        )
        let result = await AgentJobCoordinator.resolveWorktreeWorkingDirectory(
            baseDirectory: URL(fileURLWithPath: "/Users/dev/mytty"),
            branch: "-bad",
            preparer: preparer
        )
        #expect(result == .failure(AgentControlFailure(
            "invalid-worktree-branch"
        )))
        #expect(preparer.lastBranch == nil)
    }
}

/// `@unchecked Sendable`: mutated only from this suite's `@MainActor` test
/// methods, which `await` each `prepareWorktree` call to completion before
/// the next runs, so there's never concurrent access to `lastDirectory`/
/// `lastBranch` in practice.
private final class StubAgentWorktreePreparer: AgentWorktreePreparing,
    @unchecked Sendable
{
    private let result: Result<URL, AgentControlFailure>
    private(set) var lastDirectory: URL?
    private(set) var lastBranch: String?

    init(result: Result<URL, AgentControlFailure>) {
        self.result = result
    }

    func prepareWorktree(
        forDirectory directory: URL,
        branch: String
    ) async -> Result<URL, AgentControlFailure> {
        lastDirectory = directory
        lastBranch = branch
        return result
    }
}
