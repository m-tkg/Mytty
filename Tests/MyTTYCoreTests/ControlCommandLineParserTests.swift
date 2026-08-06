import Foundation
import Testing

@testable import MyTTYCore

@Suite("Control CLI argument parsing")
struct ControlCommandLineParserTests {
    @Test("list takes no arguments")
    func parsesList() throws {
        #expect(try ControlCommandLineParser.parse(["list"]) == .list)
    }

    @Test("new-tab optionally takes --cwd and --command")
    func parsesNewTab() throws {
        #expect(
            try ControlCommandLineParser.parse(["new-tab"])
                == .newTab(workingDirectory: nil, command: nil)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["new-tab", "--cwd", "/tmp/repo"]
            ) == .newTab(workingDirectory: "/tmp/repo", command: nil)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["new-tab", "--command", "claude -- task"]
            ) == .newTab(workingDirectory: nil, command: "claude -- task")
        )
        #expect(
            try ControlCommandLineParser.parse(
                [
                    "new-tab", "--cwd", "/tmp/repo",
                    "--command", "claude -- task",
                ]
            ) == .newTab(
                workingDirectory: "/tmp/repo",
                command: "claude -- task"
            )
        )
    }

    @Test("new-tab rejects stray positional arguments")
    func rejectsExtraNewTabArguments() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["new-tab", "extra"])
        }
    }

    @Test("new-tab rejects an explicitly empty --command")
    func rejectsEmptyNewTabCommand() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["new-tab", "--command", ""]
            )
        }
    }

    @Test("split requires a pane id and a direction; --cwd and --command are optional")
    func parsesSplit() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "right"]
            ) == .split(
                paneID: "pane-1",
                direction: .right,
                workingDirectory: nil,
                command: nil
            )
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "down", "--cwd", "/tmp/repo"]
            ) == .split(
                paneID: "pane-1",
                direction: .down,
                workingDirectory: "/tmp/repo",
                command: nil
            )
        )
        #expect(
            try ControlCommandLineParser.parse(
                [
                    "split", "pane-1", "down", "--cwd", "/tmp/repo",
                    "--command", "codex -- task",
                ]
            ) == .split(
                paneID: "pane-1",
                direction: .down,
                workingDirectory: "/tmp/repo",
                command: "codex -- task"
            )
        )
        #expect(
            try ControlCommandLineParser.parse(["split", "pane-1", "auto"])
                == .split(
                    paneID: "pane-1",
                    direction: .auto,
                    workingDirectory: nil,
                    command: nil
                )
        )
    }

    @Test("split defaults to auto (balanced placement) when the direction is omitted")
    func parsesSplitOmittedDirectionDefaultsToAuto() throws {
        #expect(
            try ControlCommandLineParser.parse(["split", "pane-1"])
                == .split(
                    paneID: "pane-1",
                    direction: .auto,
                    workingDirectory: nil,
                    command: nil
                )
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "--cwd", "/tmp/repo"]
            ) == .split(
                paneID: "pane-1",
                direction: .auto,
                workingDirectory: "/tmp/repo",
                command: nil
            )
        )
    }

    @Test("split rejects an explicitly empty --command")
    func rejectsEmptySplitCommand() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "right", "--command", ""]
            )
        }
    }

    @Test("split rejects an unknown direction")
    func rejectsUnknownDirection() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "sideways"]
            )
        }
    }

    @Test("split rejects stray positional arguments beyond pane id and direction")
    func rejectsExtraSplitArguments() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "right", "extra"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["split"])
        }
    }

    @Test("send parses the --enter flag independent of position")
    func parsesSend() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["send", "pane-1", "hello", "--enter"]
            ) == .send(paneID: "pane-1", text: "hello", pressEnter: true)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["send", "--enter", "pane-1", "hello"]
            ) == .send(paneID: "pane-1", text: "hello", pressEnter: true)
        )
        #expect(
            try ControlCommandLineParser.parse(["send", "pane-1", "hello"])
                == .send(paneID: "pane-1", text: "hello", pressEnter: false)
        )
    }

    @Test("send-key splits comma-separated modifiers")
    func parsesSendKey() throws {
        #expect(
            try ControlCommandLineParser.parse(
                [
                    "send-key", "pane-1", "escape",
                    "--modifiers", "shift,control",
                ]
            ) == .sendKey(
                paneID: "pane-1",
                key: "escape",
                modifiers: ["shift", "control"]
            )
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["send-key", "pane-1", "escape"]
            ) == .sendKey(paneID: "pane-1", key: "escape", modifiers: [])
        )
    }

    @Test("wait requires --until and defaults the timeout")
    func parsesWait() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["wait", "pane-1", "--until", "idle"]
            ) == .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 120)
        )
        #expect(
            try ControlCommandLineParser.parse(
                [
                    "wait", "pane-1", "--until", "attention",
                    "--timeout-seconds", "30",
                ]
            ) == .wait(
                paneID: "pane-1",
                until: .attention,
                timeoutSeconds: 30
            )
        )
    }

    @Test("wait rejects a missing --until")
    func rejectsWaitWithoutUntil() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["wait", "pane-1"])
        }
    }

    @Test("events omits --after as nil (establish a cursor) and defaults --timeout to 30")
    func parsesEventsDefaults() throws {
        #expect(
            try ControlCommandLineParser.parse(["events"])
                == .events(afterSequence: nil, timeoutSeconds: 30)
        )
    }

    @Test("events treats an explicit --after 0 as a fetch cursor, not establishment")
    func parsesEventsAfterZero() throws {
        #expect(
            try ControlCommandLineParser.parse(["events", "--after", "0"])
                == .events(afterSequence: 0, timeoutSeconds: 30)
        )
    }

    @Test("events parses --after and --timeout")
    func parsesEventsWithOptions() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["events", "--after", "42", "--timeout", "10"]
            ) == .events(afterSequence: 42, timeoutSeconds: 10)
        )
    }

    @Test("events clamps --timeout to 600")
    func eventsClampsTimeout() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["events", "--timeout", "999999"]
            ) == .events(afterSequence: nil, timeoutSeconds: 600)
        )
    }

    @Test("events rejects a non-numeric or negative --after")
    func eventsRejectsInvalidAfter() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["events", "--after", "not-a-number"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["events", "--after", "-1"])
        }
    }

    @Test("events rejects a non-numeric or negative --timeout")
    func eventsRejectsInvalidTimeout() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["events", "--timeout", "not-a-number"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["events", "--timeout", "-1"])
        }
    }

    @Test("events rejects stray positional arguments")
    func eventsRejectsExtraArguments() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["events", "extra"])
        }
    }

    @Test("waitTimeoutSeconds surfaces the events timeout too")
    func waitTimeoutSecondsCoversEvents() {
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(
                for: .events(afterSequence: 5, timeoutSeconds: 45)
            ) == 45
        )
    }

    @Test("read, close-pane, focus, and park each require exactly one pane id")
    func parsesSingleArgumentCommands() throws {
        #expect(
            try ControlCommandLineParser.parse(["read", "pane-1"])
                == .read(paneID: "pane-1")
        )
        #expect(
            try ControlCommandLineParser.parse(["close-pane", "pane-1"])
                == .closePane(paneID: "pane-1")
        )
        #expect(
            try ControlCommandLineParser.parse(["focus", "pane-1"])
                == .focus(paneID: "pane-1")
        )
        #expect(
            try ControlCommandLineParser.parse(["park", "pane-1"])
                == .parkPane(paneID: "pane-1")
        )
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["read"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["read", "pane-1", "extra"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["park"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["park", "pane-1", "extra"])
        }
    }

    @Test("an empty or unknown command is rejected")
    func rejectsEmptyOrUnknownCommand() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse([])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["not-a-command"])
        }
    }

    @Test("waitTimeoutSeconds only surfaces a value for wait requests")
    func waitTimeoutSecondsHelper() {
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(
                for: .wait(
                    paneID: "pane-1",
                    until: .idle,
                    timeoutSeconds: 45
                )
            ) == 45
        )
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(for: .list) == nil
        )
    }

    @Test("parseInvocation recognizes guide, --help, -h, and no arguments")
    func parsesInvocationNonSocketCommands() throws {
        #expect(
            try ControlCommandLineParser.parseInvocation(["guide"]) == .guide
        )
        #expect(
            try ControlCommandLineParser.parseInvocation(["--help"]) == .help
        )
        #expect(
            try ControlCommandLineParser.parseInvocation(["-h"]) == .help
        )
        #expect(try ControlCommandLineParser.parseInvocation([]) == .help)
    }

    @Test("parseInvocation wraps existing commands unchanged")
    func parsesInvocationWrapsRequests() throws {
        #expect(
            try ControlCommandLineParser.parseInvocation(["list"])
                == .request(.list)
        )
        #expect(
            try ControlCommandLineParser.parseInvocation(
                ["send", "pane-1", "hello", "--enter"]
            ) == .request(
                .send(paneID: "pane-1", text: "hello", pressEnter: true)
            )
        )
    }

    @Test("parseInvocation still rejects unknown commands")
    func parsesInvocationRejectsUnknownCommand() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parseInvocation(["not-a-command"])
        }
    }

    @Test("paneTeamGuide covers provider launch commands and the idle wait")
    func paneTeamGuideContent() {
        let guide = ControlCommandLineParser.paneTeamGuide
        #expect(guide.contains("claude --permission-mode acceptEdits"))
        #expect(guide.contains("codex -s workspace-write -a never"))
        #expect(guide.contains("cursor-agent --force"))
        #expect(guide.contains("antigravity"))
        #expect(guide.contains("--until idle"))
        #expect(guide.contains("MYTTY_CTL_BIN"))
        #expect(guide.contains("MYTTY_SURFACE_ID"))
        #expect(guide.contains("MYTTY_CONTROL_SOCKET"))
        #expect(guide.contains("still be initializing and drops"))
    }

    @Test("paneTeamGuide warns that Codex's own sandbox blocks every mytty-ctl command, not just wait")
    func paneTeamGuideCodexSandboxNote() {
        let guide = ControlCommandLineParser.paneTeamGuide
        #expect(guide.contains("CODEX SANDBOX NOTE"))
        #expect(guide.contains("socketOperation(1)"))
        #expect(guide.contains("EPERM"))
        #expect(guide.contains("outside the sandbox"))
    }

    @Test("paneTeamGuide prefers the high-level agent API and stages a full example")
    func paneTeamGuidePrefersAgentAPI() {
        let guide = ControlCommandLineParser.paneTeamGuide
        #expect(guide.contains("agent spawn"))
        #expect(guide.contains("agent wait"))
        #expect(guide.contains("agent result"))
        #expect(guide.contains("agent send"))
        #expect(guide.contains("agent focus"))
        #expect(guide.contains("agent close"))
        #expect(guide.contains("--until running"))
        #expect(guide.contains("--until attention"))
        #expect(guide.contains("--until completed"))
        #expect(guide.contains("escape hatch"))
        // The staged example from the spec: two parallel investigations,
        // then an implementation worker fed their combined findings, then
        // a review worker, then follow-up corrections.
        #expect(guide.contains("--access review"))
        #expect(guide.contains("--access workspace-write"))
    }

    @Test("paneTeamGuide documents balanced placement and parking finished workers")
    func paneTeamGuideDocumentsAutoAndPark() {
        let guide = ControlCommandLineParser.paneTeamGuide
        // --direction auto / balanced placement.
        #expect(guide.contains("--direction <left|right|up|down|auto>"))
        #expect(guide.contains("balanced"))
        // agent park / park, and the done_<tab>_<id> naming.
        #expect(guide.contains("agent park"))
        #expect(guide.contains("done_"))
        #expect(guide.contains("agent close"))
    }

    // MARK: - agent spawn

    @Test("agent spawn applies every default")
    func agentSpawnDefaults() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "codex",
                "--task", "investigate",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        // An omitted `--access` is sent as `nil`, not defaulted to
        // workspace-write client-side -- the server resolves it via
        // `AgentAccessResolution` (see `agentAccessOmittedProducesNilAccess`
        // below and the resolution-order tests in
        // `AgentAccessResolutionTests`). An omitted `--direction`
        // likewise defaults to `.auto` (balanced placement), not a fixed
        // "right".
        #expect(request == .spawnAgent(
            anchorPaneID: "anchor-1",
            direction: .auto,
            provider: .codex,
            cwd: nil,
            access: nil,
            model: nil,
            task: "investigate",
            label: nil,
            worktreeBranch: nil
        ))
    }

    @Test("agent spawn accepts an explicit --direction auto")
    func agentSpawnExplicitAuto() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "codex",
                "--direction", "auto",
                "--task", "investigate",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        guard case let .spawnAgent(_, direction, _, _, _, _, _, _, _) = request
        else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(direction == .auto)
    }

    @Test("agent spawn without --access produces a nil access field")
    func agentAccessOmittedProducesNilAccess() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "codex",
                "--task", "investigate",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        guard case let .spawnAgent(_, _, _, _, access, _, _, _, _) = request
        else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(access == nil)
    }

    @Test("agent spawn with --access workspace-write produces that value")
    func agentAccessExplicitWorkspaceWriteProducesValue() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "codex",
                "--access", "workspace-write",
                "--task", "investigate",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        guard case let .spawnAgent(_, _, _, _, access, _, _, _, _) = request
        else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(access == .workspaceWrite)
    }

    @Test("agent spawn accepts every explicit option")
    func agentSpawnExplicitOptions() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--anchor", "pane-9",
                "--direction", "down",
                "--provider", "claude",
                "--cwd", "/tmp/repo",
                "--access", "review",
                "--model", "sonnet",
                "--task", "review the diff",
                "--label", "review-a",
                "--worktree", "feat/review-a",
            ],
            environment: [:]
        )
        #expect(request == .spawnAgent(
            anchorPaneID: "pane-9",
            direction: .down,
            provider: .claude,
            cwd: "/tmp/repo",
            access: .review,
            model: "sonnet",
            task: "review the diff",
            label: "review-a",
            worktreeBranch: "feat/review-a"
        ))
    }

    @Test("agent spawn accepts --access inherit")
    func agentSpawnAccessInherit() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "claude",
                "--access", "inherit",
                "--task", "pair on the fix",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        #expect(request == .spawnAgent(
            anchorPaneID: "anchor-1",
            direction: .auto,
            provider: .claude,
            cwd: nil,
            access: .inherit,
            model: nil,
            task: "pair on the fix",
            label: nil,
            worktreeBranch: nil
        ))
    }

    @Test("agent spawn --model is optional and defaults to nil")
    func agentSpawnModelDefaultsToNil() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "codex",
                "--task", "investigate",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        guard case let .spawnAgent(_, _, _, _, _, model, _, _, _) = request
        else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(model == nil)
    }

    @Test("agent spawn --worktree is optional and defaults to nil")
    func agentSpawnWorktreeDefaultsToNil() throws {
        let request = try ControlCommandLineParser.parse(
            [
                "agent", "spawn",
                "--provider", "codex",
                "--task", "investigate",
            ],
            environment: ["MYTTY_SURFACE_ID": "anchor-1"]
        )
        guard case let .spawnAgent(
            _, _, _, _, _, _, _, _, worktreeBranch
        ) = request else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(worktreeBranch == nil)
    }

    @Test("agent spawn rejects an invalid --worktree branch")
    func agentSpawnRejectsInvalidWorktreeBranch() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--task", "x", "--worktree", "-bad",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--task", "x", "--worktree", "",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn --worktree requires a value")
    func agentSpawnWorktreeRequiresValue() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--task", "x", "--worktree",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn --worktree works with --task-file too")
    func agentSpawnWorktreeWithTaskFile() throws {
        let invocation = try ControlCommandLineParser.parseInvocation(
            [
                "agent", "spawn",
                "--anchor", "pane-1",
                "--provider", "cursor",
                "--task-file", "/tmp/does-not-exist-anywhere.txt",
                "--worktree", "feat/worker-a",
            ],
            environment: [:]
        )
        guard case let .agentSpawnPendingTaskFile(pending) = invocation else {
            Issue.record("expected .agentSpawnPendingTaskFile, got \(invocation)")
            return
        }
        #expect(pending.worktreeBranch == "feat/worker-a")
        let request = try ControlCommandLineParser.spawnAgentRequest(
            from: pending,
            task: "do it"
        )
        guard case let .spawnAgent(
            _, _, _, _, _, _, _, _, worktreeBranch
        ) = request else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(worktreeBranch == "feat/worker-a")
    }

    @Test("agent spawn requires --anchor or MYTTY_SURFACE_ID")
    func agentSpawnRequiresAnchor() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "spawn", "--provider", "codex", "--task", "x"],
                environment: [:]
            )
        }
    }

    @Test("agent spawn rejects an unknown provider or access policy")
    func agentSpawnRejectsUnknownProviderOrAccess() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "gpt", "--task", "x",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--access", "yolo", "--task", "x",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn rejects an unknown direction")
    func agentSpawnRejectsUnknownDirection() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--direction", "sideways", "--task", "x",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn requires exactly one of --task or --task-file")
    func agentSpawnTaskExclusivity() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "spawn", "--provider", "codex"],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--task", "x", "--task-file", "/tmp/task.txt",
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn rejects an empty task")
    func agentSpawnRejectsEmptyTask() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "spawn", "--provider", "codex", "--task", ""],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn rejects a task too large for the request envelope")
    func agentSpawnRejectsOversizedTask() {
        let hugeTask = String(repeating: "a", count: 70_000)
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                [
                    "agent", "spawn", "--provider", "codex",
                    "--task", hugeTask,
                ],
                environment: ["MYTTY_SURFACE_ID": "anchor-1"]
            )
        }
    }

    @Test("agent spawn --task-file resolves via parseInvocation without reading the file")
    func agentSpawnTaskFileInvocation() throws {
        let invocation = try ControlCommandLineParser.parseInvocation(
            [
                "agent", "spawn",
                "--anchor", "pane-1",
                "--provider", "cursor",
                "--access", "review",
                "--task-file", "/tmp/does-not-exist-anywhere.txt",
                "--label", "investigate-b",
            ],
            environment: [:]
        )
        #expect(invocation == .agentSpawnPendingTaskFile(
            ControlCommandLineParser.PendingAgentSpawnRequest(
                anchorPaneID: "pane-1",
                direction: .auto,
                provider: .cursor,
                cwd: nil,
                access: .review,
                model: nil,
                label: "investigate-b",
                worktreeBranch: nil,
                taskFilePath: "/tmp/does-not-exist-anywhere.txt"
            )
        ))
    }

    @Test("spawnAgentRequest(from:task:) validates the resolved task text")
    func spawnAgentRequestValidatesResolvedTask() throws {
        let pending = ControlCommandLineParser.PendingAgentSpawnRequest(
            anchorPaneID: "pane-1",
            direction: .right,
            provider: .codex,
            cwd: nil,
            access: .workspaceWrite,
            model: "gpt-5.2",
            label: nil,
            worktreeBranch: nil,
            taskFilePath: "/tmp/task.txt"
        )
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.spawnAgentRequest(
                from: pending,
                task: ""
            )
        }
        let request = try ControlCommandLineParser.spawnAgentRequest(
            from: pending,
            task: "do it"
        )
        #expect(request == .spawnAgent(
            anchorPaneID: "pane-1",
            direction: .right,
            provider: .codex,
            cwd: nil,
            access: .workspaceWrite,
            model: "gpt-5.2",
            task: "do it",
            label: nil,
            worktreeBranch: nil
        ))
    }

    // MARK: - agent wait/result/send/focus/close

    @Test("agent wait requires --until and defaults the timeout")
    func agentWaitDefaults() throws {
        let jobID = AgentJobID()
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "wait", jobID.rawValue.uuidString, "--until", "running"]
            ) == .waitAgent(jobID: jobID, until: .running, timeoutSeconds: 120)
        )
        #expect(
            try ControlCommandLineParser.parse(
                [
                    "agent", "wait", jobID.rawValue.uuidString,
                    "--until", "completed", "--timeout-seconds", "45",
                ]
            ) == .waitAgent(
                jobID: jobID,
                until: .completed,
                timeoutSeconds: 45
            )
        )
    }

    @Test("agent wait rejects an invalid job UUID")
    func agentWaitRejectsInvalidJobID() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "wait", "not-a-uuid", "--until", "running"]
            )
        }
    }

    @Test("agent result, focus, close, and park each require exactly one job id")
    func agentSingleArgumentCommands() throws {
        let jobID = AgentJobID()
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "result", jobID.rawValue.uuidString]
            ) == .agentResult(jobID: jobID)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "focus", jobID.rawValue.uuidString]
            ) == .focusAgent(jobID: jobID)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "close", jobID.rawValue.uuidString]
            ) == .closeAgent(jobID: jobID)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "park", jobID.rawValue.uuidString]
            ) == .parkAgent(jobID: jobID)
        )
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["agent", "result"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "result", "not-a-uuid"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["agent", "park"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "park", "not-a-uuid"]
            )
        }
    }

    @Test("agent send parses the --enter flag and the job id")
    func agentSendParsing() throws {
        let jobID = AgentJobID()
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "send", jobID.rawValue.uuidString, "hello", "--enter"]
            ) == .sendAgent(jobID: jobID, text: "hello", pressEnter: true)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["agent", "send", jobID.rawValue.uuidString, "hello"]
            ) == .sendAgent(jobID: jobID, text: "hello", pressEnter: false)
        )
    }

    @Test("an unknown agent subcommand is rejected")
    func rejectsUnknownAgentSubcommand() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["agent", "not-a-subcommand"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["agent"])
        }
    }

    @Test("waitTimeoutSeconds surfaces agent wait timeouts too")
    func waitTimeoutSecondsCoversAgentWait() {
        let jobID = AgentJobID()
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(
                for: .waitAgent(
                    jobID: jobID,
                    until: .running,
                    timeoutSeconds: 45
                )
            ) == 45
        )
    }

    @Test("parses status with the env-default pane, --pane, and --clear")
    func statusParsing() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["status", "running tests"],
                environment: ["MYTTY_SURFACE_ID": "pane-env"]
            ) == .setPaneStatus(paneID: "pane-env", status: "running tests")
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["status", "reviewing diff", "--pane", "pane-9"],
                environment: ["MYTTY_SURFACE_ID": "pane-env"]
            ) == .setPaneStatus(paneID: "pane-9", status: "reviewing diff")
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["status", "--clear"],
                environment: ["MYTTY_SURFACE_ID": "pane-env"]
            ) == .setPaneStatus(paneID: "pane-env", status: nil)
        )
    }

    @Test("rejects invalid status invocations")
    func rejectsInvalidStatus() {
        // No pane resolvable at all.
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["status", "hello"],
                environment: [:]
            )
        }
        // Empty, control characters, too long, or text alongside --clear.
        for arguments in [
            ["status", ""],
            ["status", "line\nbreak"],
            ["status", String(repeating: "x", count: 101)],
            ["status", "text", "--clear"],
            ["status"],
        ] {
            #expect(throws: ControlCommandLineError.self) {
                try ControlCommandLineParser.parse(
                    arguments,
                    environment: ["MYTTY_SURFACE_ID": "pane-env"]
                )
            }
        }
    }

    @Test("parses integration subcommands")
    func integrationParsing() throws {
        #expect(
            try ControlCommandLineParser.parse(["integration", "list"])
                == .integrationList
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["integration", "enable", "claude-code"]
            ) == .integrationEnable(provider: .claudeCode)
        )
        #expect(
            try ControlCommandLineParser.parse(["integration", "repair"])
                == .integrationRepair(provider: nil)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["integration", "repair", "opencode"]
            ) == .integrationRepair(provider: .openCode)
        )
        #expect(
            try ControlCommandLineParser.parseInvocation(
                ["integration", "list"],
                environment: [:]
            ) == .request(.integrationList)
        )
    }

    @Test("rejects invalid integration arguments")
    func rejectsInvalidIntegrationArguments() {
        // "claude" is agent spawn vocabulary; integrations use the
        // five AgentProvider identifiers ("claude-code", ...).
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["integration", "enable", "claude"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["integration", "enable"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["integration"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["integration", "not-a-subcommand"]
            )
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["integration", "list", "extra"]
            )
        }
    }

    @Test("integration enable and repair carry the approval timeout")
    func integrationApprovalTimeout() {
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(
                for: .integrationEnable(provider: .codex)
            ) == ControlCommandLineParser.integrationApprovalTimeoutSeconds
        )
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(
                for: .integrationRepair(provider: nil)
            ) == ControlCommandLineParser.integrationApprovalTimeoutSeconds
        )
        #expect(
            ControlCommandLineParser.waitTimeoutSeconds(
                for: .integrationList
            ) == nil
        )
    }

    @Test("usage and guide document the integration commands")
    func integrationDocumentation() {
        #expect(ControlCommandLineParser.usage.contains("integration enable"))
        let guide = ControlCommandLineParser.paneTeamGuide
        #expect(guide.contains("HOOK INTEGRATIONS"))
        #expect(guide.contains("integration enable"))
        #expect(guide.contains("integration-declined"))
        #expect(guide.contains("ONLY A HUMAN"))
    }
}
