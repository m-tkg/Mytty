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
}
