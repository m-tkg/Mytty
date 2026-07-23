import Foundation
import Testing

@testable import MyTTYCore

@Suite("Control protocol codec")
struct ControlProtocolTests {
    @Test("round-trips every request case through JSON")
    func requestRoundTrip() throws {
        let requests: [ControlRequest] = [
            .list,
            .newTab(workingDirectory: nil, command: nil),
            .newTab(workingDirectory: "/tmp/repo", command: nil),
            .newTab(
                workingDirectory: "/tmp/repo",
                command: "claude --permission-mode acceptEdits -- task"
            ),
            .split(
                paneID: "pane-1",
                direction: .right,
                workingDirectory: nil,
                command: nil
            ),
            .split(
                paneID: "pane-1",
                direction: .down,
                workingDirectory: "/tmp/repo",
                command: nil
            ),
            .split(
                paneID: "pane-1",
                direction: .down,
                workingDirectory: "/tmp/repo",
                command: "codex -s workspace-write -a never -- task"
            ),
            .send(paneID: "pane-1", text: "hello\n", pressEnter: true),
            .sendKey(
                paneID: "pane-1",
                key: "escape",
                modifiers: ["shift", "control"]
            ),
            .read(paneID: "pane-1"),
            .wait(
                paneID: "pane-1",
                until: .idle,
                timeoutSeconds: 120
            ),
            .wait(
                paneID: "pane-1",
                until: .attention,
                timeoutSeconds: 30.5
            ),
            .closePane(paneID: "pane-1"),
            .focus(paneID: "pane-1"),
            .spawnAgent(
                anchorPaneID: "pane-1",
                direction: .right,
                provider: .codex,
                cwd: nil,
                access: .workspaceWrite,
                model: nil,
                task: "investigate the bug",
                label: nil
            ),
            .spawnAgent(
                anchorPaneID: "pane-1",
                direction: .down,
                provider: .claude,
                cwd: "/tmp/repo",
                access: .review,
                model: "sonnet",
                task: "review the diff",
                label: "review-a"
            ),
            .spawnAgent(
                anchorPaneID: "pane-1",
                direction: .right,
                provider: .claude,
                cwd: nil,
                access: .inherit,
                model: nil,
                task: "pair on the fix",
                label: "worker-a"
            ),
            .waitAgent(
                jobID: AgentJobID(),
                until: .running,
                timeoutSeconds: 120
            ),
            .waitAgent(
                jobID: AgentJobID(),
                until: .completed,
                timeoutSeconds: 30.5
            ),
            .agentResult(jobID: AgentJobID()),
            .sendAgent(jobID: AgentJobID(), text: "hi", pressEnter: true),
            .focusAgent(jobID: AgentJobID()),
            .closeAgent(jobID: AgentJobID()),
        ]

        for request in requests {
            let encoded = try ControlMessageCodec.encode(request)
            let decoded: ControlRequest = try ControlMessageCodec.decode(
                encoded
            )
            #expect(decoded == request)
        }
    }

    @Test("round-trips every response case through JSON")
    func responseRoundTrip() throws {
        let responses: [ControlResponse] = [
            .list(panes: [
                ControlPaneInfo(
                    paneID: "pane-1",
                    windowID: "window-1",
                    tabID: "tab-1",
                    title: "claude",
                    command: "claude",
                    workingDirectory: "/tmp/repo",
                    isActive: true,
                    provider: "claude-code",
                    agentState: "running"
                ),
            ]),
            .list(panes: []),
            .pane(paneID: "pane-2"),
            .ok,
            .content(
                ControlPaneContent(
                    paneID: "pane-1",
                    text: "$ echo hi\nhi\n",
                    cursorRow: 1,
                    cursorColumn: 0
                )
            ),
            .waitResult(state: "idle", timedOut: false),
            .waitResult(state: nil, timedOut: true),
            .failure(code: "pane-not-found"),
            .agentJob(
                AgentJobSnapshot(
                    jobID: AgentJobID(),
                    paneID: TerminalSurfaceID(),
                    provider: .codex,
                    label: "investigation-a",
                    state: .launching,
                    runID: nil,
                    sessionID: nil,
                    message: nil
                )
            ),
            .agentWaitResult(
                job: AgentJobSnapshot(
                    jobID: AgentJobID(),
                    paneID: TerminalSurfaceID(),
                    provider: .claude,
                    label: nil,
                    state: .waitingApproval,
                    runID: AgentRunID(),
                    sessionID: "session-1",
                    message: "needs approval"
                ),
                timedOut: false
            ),
            .agentResult(
                job: AgentJobSnapshot(
                    jobID: AgentJobID(),
                    paneID: TerminalSurfaceID(),
                    provider: .cursor,
                    label: nil,
                    state: .succeeded,
                    runID: AgentRunID(),
                    sessionID: nil,
                    message: "done"
                ),
                content: ControlPaneContent(
                    paneID: "pane-1",
                    text: "screen text",
                    cursorRow: 3,
                    cursorColumn: 1
                )
            ),
        ]

        for response in responses {
            let encoded = try ControlMessageCodec.encode(response)
            let decoded: ControlResponse = try ControlMessageCodec.decode(
                encoded
            )
            #expect(decoded == response)
        }
    }

    @Test("rejects malformed request payloads instead of crashing")
    func rejectsMalformedRequest() {
        let malformed = Data("{\"type\":\"not-a-real-command\"}".utf8)
        #expect(throws: (any Error).self) {
            let _: ControlRequest = try ControlMessageCodec.decode(malformed)
        }
    }

    @Test("rejects a request missing its required fields")
    func rejectsIncompleteRequest() {
        let missingPaneID = Data("{\"type\":\"send\"}".utf8)
        #expect(throws: (any Error).self) {
            let _: ControlRequest = try ControlMessageCodec.decode(
                missingPaneID
            )
        }
    }

    @Test("decoding a legacy spawnAgent payload without a model key yields nil")
    func decodesLegacySpawnAgentWithoutModel() throws {
        let legacy = Data("""
        {"type":"spawnAgent","anchorPaneID":"pane-1","direction":"right",\
        "provider":"codex","access":"workspace-write","task":"investigate"}
        """.utf8)
        let decoded: ControlRequest = try ControlMessageCodec.decode(legacy)
        #expect(decoded == .spawnAgent(
            anchorPaneID: "pane-1",
            direction: .right,
            provider: .codex,
            cwd: nil,
            access: .workspaceWrite,
            model: nil,
            task: "investigate",
            label: nil
        ))
    }

    @Test("decodes a legacy newTab/split payload without a command key")
    func decodesLegacyNewTabAndSplitWithoutCommand() throws {
        let legacyNewTab = Data("""
        {"type":"newTab","workingDirectory":"/tmp/repo"}
        """.utf8)
        let decodedNewTab: ControlRequest = try ControlMessageCodec.decode(
            legacyNewTab
        )
        #expect(decodedNewTab == .newTab(
            workingDirectory: "/tmp/repo",
            command: nil
        ))

        let legacySplit = Data("""
        {"type":"split","paneID":"pane-1","direction":"right"}
        """.utf8)
        let decodedSplit: ControlRequest = try ControlMessageCodec.decode(
            legacySplit
        )
        #expect(decodedSplit == .split(
            paneID: "pane-1",
            direction: .right,
            workingDirectory: nil,
            command: nil
        ))
    }

    @Test("rejects an agent request missing its required fields")
    func rejectsIncompleteAgentRequest() {
        let missingTask = Data("""
        {"type":"spawnAgent","anchorPaneID":"pane-1","direction":"right",\
        "provider":"codex","access":"workspace-write"}
        """.utf8)
        #expect(throws: (any Error).self) {
            let _: ControlRequest = try ControlMessageCodec.decode(
                missingTask
            )
        }

        let missingJobID = Data("{\"type\":\"waitAgent\",\"until\":\"running\",\"timeoutSeconds\":120}".utf8)
        #expect(throws: (any Error).self) {
            let _: ControlRequest = try ControlMessageCodec.decode(
                missingJobID
            )
        }
    }
}
