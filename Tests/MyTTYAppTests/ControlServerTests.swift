import Darwin
import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// Drives the real `ControlServer` over an actual Unix-domain socket using
/// `ControlSocketClient` (the same client `mytty-ctl` uses), to catch
/// integration bugs in framing/encoding that a delegate-only unit test
/// can't see.
@MainActor
@Suite("Control server", .serialized)
struct ControlServerTests {
    @Test("list returns the delegate's panes")
    func listReturnsPanes() async throws {
        let delegate = StubControlDelegate()
        delegate.panes = [
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
        ]
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let response = try await perform(.list, to: socketURL)
        guard case let .list(panes) = response else {
            Issue.record("expected .list, got \(response)")
            return
        }
        #expect(panes == delegate.panes)
    }

    @Test("newTab and split forward the working directory and return the new pane id")
    func newTabAndSplit() async throws {
        let delegate = StubControlDelegate()
        delegate.nextPaneID = "new-pane"
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let newTabResponse = try await perform(
            .newTab(workingDirectory: "/tmp/repo"),
            to: socketURL
        )
        #expect(newTabResponse == .pane(paneID: "new-pane"))
        #expect(delegate.lastNewTabWorkingDirectory == "/tmp/repo")

        let splitResponse = try await perform(
            .split(
                paneID: "pane-1",
                direction: .right,
                workingDirectory: "/tmp/other"
            ),
            to: socketURL
        )
        #expect(splitResponse == .pane(paneID: "new-pane"))
        #expect(delegate.lastSplitPaneID == "pane-1")
        #expect(delegate.lastSplitDirection == .right)
        #expect(delegate.lastSplitWorkingDirectory == "/tmp/other")
    }

    @Test("send, sendKey, closePane, and focus report failure for an unknown pane")
    func unknownPaneFailures() async throws {
        let delegate = StubControlDelegate()
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        #expect(
            try await perform(
                .send(paneID: "missing", text: "hi", pressEnter: false),
                to: socketURL
            ) == .failure(code: "pane-not-found")
        )
        #expect(
            try await perform(
                .sendKey(paneID: "missing", key: "escape", modifiers: []),
                to: socketURL
            ) == .failure(code: "pane-not-found")
        )
        #expect(
            try await perform(.closePane(paneID: "missing"), to: socketURL)
                == .failure(code: "pane-not-found")
        )
        #expect(
            try await perform(.focus(paneID: "missing"), to: socketURL)
                == .failure(code: "pane-not-found")
        )
        #expect(
            try await perform(.read(paneID: "missing"), to: socketURL)
                == .failure(code: "pane-not-found")
        )
    }

    @Test("send delivers text to the right pane")
    func sendDeliversText() async throws {
        let delegate = StubControlDelegate()
        delegate.knownPaneIDs = ["pane-1"]
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let response = try await perform(
            .send(paneID: "pane-1", text: "hello", pressEnter: true),
            to: socketURL
        )
        #expect(response == .ok)
        #expect(delegate.sentText == "hello")
        #expect(delegate.sentPressEnter == true)
    }

    @Test("read returns the delegate's pane content")
    func readReturnsContent() async throws {
        let delegate = StubControlDelegate()
        delegate.knownPaneIDs = ["pane-1"]
        delegate.content["pane-1"] = ControlPaneContent(
            paneID: "pane-1",
            text: "hi",
            cursorRow: 0,
            cursorColumn: 2
        )
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let response = try await perform(
            .read(paneID: "pane-1"),
            to: socketURL
        )
        #expect(response == .content(delegate.content["pane-1"]!))
    }

    @Test("wait resolves immediately once the pane reaches the target state")
    func waitResolvesOnMatchingState() async throws {
        let delegate = StubControlDelegate()
        delegate.knownPaneIDs = ["pane-1"]
        delegate.agentStates["pane-1"] = .idle
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let start = Date()
        let response = try await perform(
            .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 10),
            to: socketURL,
            timeoutSeconds: 10
        )
        #expect(response == .waitResult(state: "idle", timedOut: false))
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test("wait times out when the condition is never satisfied")
    func waitTimesOut() async throws {
        let delegate = StubControlDelegate()
        delegate.knownPaneIDs = ["pane-1"]
        delegate.agentStates["pane-1"] = .running
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let response = try await perform(
            .wait(paneID: "pane-1", until: .idle, timeoutSeconds: 1),
            to: socketURL,
            timeoutSeconds: 1
        )
        #expect(response == .waitResult(state: "running", timedOut: true))
    }

    @Test("wait fails fast for a pane that doesn't exist")
    func waitFailsForUnknownPane() async throws {
        let delegate = StubControlDelegate()
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let response = try await perform(
            .wait(paneID: "missing", until: .idle, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        #expect(response == .failure(code: "pane-not-found"))
    }

    @Test("malformed JSON is rejected without crashing the server")
    func rejectsMalformedRequest() async throws {
        let delegate = StubControlDelegate()
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        let response = try await Task.detached {
            try Self.sendRaw(Data("not json at all\n".utf8), to: socketURL)
        }.value
        #expect(response == .failure(code: "invalid-request"))
    }

    // MARK: - Helpers

    /// `ControlSocketClient.send` blocks synchronously on Darwin socket
    /// calls; running it directly on this `@MainActor` test's thread would
    /// starve the server's own `Task { @MainActor in ... }` handler of the
    /// main actor it needs to produce a reply, deadlocking until the
    /// client's receive timeout fires. `Task.detached` moves the blocking
    /// call off the main actor so the server can actually respond —
    /// `AgentEventServerTests` uses the same pattern for the same reason.
    private func perform(
        _ request: ControlRequest,
        to socketURL: URL,
        timeoutSeconds: Double? = nil
    ) async throws -> ControlResponse {
        try await Task.detached {
            try ControlSocketClient().send(
                request,
                to: socketURL,
                timeoutSeconds: timeoutSeconds
            )
        }.value
    }

    private func makeServer(
        delegate: StubControlDelegate
    ) async throws -> (ControlServer, URL) {
        // sockaddr_un.sun_path is only 104 bytes on Darwin, so the temp
        // directory's UUID component plus the socket filename has to stay
        // short — a longer descriptive name here overflows it.
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                String(UUID().uuidString.prefix(8)),
                isDirectory: true
            )
            .appendingPathComponent("c.sock", isDirectory: false)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let server = ControlServer(
            socketURL: socketURL,
            onError: { error in Issue.record("server error: \(error)") }
        )
        server.delegate = delegate
        try server.start()
        return (server, socketURL)
    }

    private struct RawConnectError: Error {}

    private static nonisolated func sendRaw(
        _ data: Data,
        to socketURL: URL
    ) throws -> ControlResponse {
        // Mirrors ControlSocketClient's framing without going through the
        // typed request encoder, so an invalid payload can reach the wire.
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard connectResult == 0 else { throw RawConnectError() }
        data.withUnsafeBytes { bytes in
            _ = send(descriptor, bytes.baseAddress, bytes.count, 0)
        }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !response.contains(0x0A) {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            response.append(contentsOf: buffer.prefix(count))
        }
        return try ControlMessageCodec.decode(response)
    }
}

@MainActor
private final class StubControlDelegate: ControlServerDelegate {
    var panes: [ControlPaneInfo] = []
    var nextPaneID: String?
    var knownPaneIDs: Set<String> = []
    var content: [String: ControlPaneContent] = [:]
    var agentStates: [String: AgentRunState] = [:]

    var lastNewTabWorkingDirectory: String?
    var lastSplitPaneID: String?
    var lastSplitDirection: ControlSplitDirection?
    var lastSplitWorkingDirectory: String?
    var sentText: String?
    var sentPressEnter: Bool?

    func controlServerListPanes(_ server: ControlServer) -> [ControlPaneInfo] {
        panes
    }

    func controlServer(
        _ server: ControlServer,
        newTabWithWorkingDirectory workingDirectory: String?
    ) -> String? {
        lastNewTabWorkingDirectory = workingDirectory
        return nextPaneID
    }

    func controlServer(
        _ server: ControlServer,
        splitPaneID paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?
    ) -> String? {
        lastSplitPaneID = paneID
        lastSplitDirection = direction
        lastSplitWorkingDirectory = workingDirectory
        return nextPaneID
    }

    func controlServer(
        _ server: ControlServer,
        sendText text: String,
        pressEnter: Bool,
        toPaneID paneID: String
    ) -> Bool {
        guard knownPaneIDs.contains(paneID) else { return false }
        sentText = text
        sentPressEnter = pressEnter
        return true
    }

    func controlServer(
        _ server: ControlServer,
        pressKey key: String,
        modifiers: [String],
        toPaneID paneID: String
    ) -> Bool {
        knownPaneIDs.contains(paneID)
    }

    func controlServer(
        _ server: ControlServer,
        contentForPaneID paneID: String
    ) -> ControlPaneContent? {
        content[paneID]
    }

    func controlServer(
        _ server: ControlServer,
        agentStateForPaneID paneID: String
    ) -> AgentRunState?? {
        guard knownPaneIDs.contains(paneID) else { return nil }
        return .some(agentStates[paneID])
    }

    func controlServer(
        _ server: ControlServer,
        closePaneID paneID: String
    ) -> Bool {
        knownPaneIDs.contains(paneID)
    }

    func controlServer(
        _ server: ControlServer,
        focusPaneID paneID: String
    ) -> Bool {
        knownPaneIDs.contains(paneID)
    }
}
