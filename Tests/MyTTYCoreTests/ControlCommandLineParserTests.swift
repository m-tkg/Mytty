import Foundation
import Testing

@testable import MyTTYCore

@Suite("Control CLI argument parsing")
struct ControlCommandLineParserTests {
    @Test("list takes no arguments")
    func parsesList() throws {
        #expect(try ControlCommandLineParser.parse(["list"]) == .list)
    }

    @Test("new-tab optionally takes --cwd")
    func parsesNewTab() throws {
        #expect(
            try ControlCommandLineParser.parse(["new-tab"])
                == .newTab(workingDirectory: nil)
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["new-tab", "--cwd", "/tmp/repo"]
            ) == .newTab(workingDirectory: "/tmp/repo")
        )
    }

    @Test("new-tab rejects stray positional arguments")
    func rejectsExtraNewTabArguments() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["new-tab", "extra"])
        }
    }

    @Test("split requires a pane id and a direction, --cwd is optional")
    func parsesSplit() throws {
        #expect(
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "right"]
            ) == .split(
                paneID: "pane-1",
                direction: .right,
                workingDirectory: nil
            )
        )
        #expect(
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "down", "--cwd", "/tmp/repo"]
            ) == .split(
                paneID: "pane-1",
                direction: .down,
                workingDirectory: "/tmp/repo"
            )
        )
    }

    @Test("split rejects an unknown direction")
    func rejectsUnknownDirection() {
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["split", "pane-1", "sideways"]
            )
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

    @Test("read, close-pane, and focus each require exactly one pane id")
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
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["read"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["read", "pane-1", "extra"])
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
        #expect(request == .spawnAgent(
            anchorPaneID: "anchor-1",
            direction: .right,
            provider: .codex,
            cwd: nil,
            access: .workspaceWrite,
            model: nil,
            task: "investigate",
            label: nil
        ))
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
            label: "review-a"
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
            direction: .right,
            provider: .claude,
            cwd: nil,
            access: .inherit,
            model: nil,
            task: "pair on the fix",
            label: nil
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
        guard case let .spawnAgent(_, _, _, _, _, model, _, _) = request else {
            Issue.record("expected .spawnAgent, got \(request)")
            return
        }
        #expect(model == nil)
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
                direction: .right,
                provider: .cursor,
                cwd: nil,
                access: .review,
                model: nil,
                label: "investigate-b",
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
            label: nil
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

    @Test("agent result, focus, and close each require exactly one job id")
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
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(["agent", "result"])
        }
        #expect(throws: ControlCommandLineError.self) {
            try ControlCommandLineParser.parse(
                ["agent", "result", "not-a-uuid"]
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
}
