import Foundation
import Testing

@testable import MyTTYCore

@Suite("Control protocol codec")
struct ControlProtocolTests {
    @Test("round-trips every request case through JSON")
    func requestRoundTrip() throws {
        let requests: [ControlRequest] = [
            .list,
            .newTab(workingDirectory: nil),
            .newTab(workingDirectory: "/tmp/repo"),
            .split(
                paneID: "pane-1",
                direction: .right,
                workingDirectory: nil
            ),
            .split(
                paneID: "pane-1",
                direction: .down,
                workingDirectory: "/tmp/repo"
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
}
