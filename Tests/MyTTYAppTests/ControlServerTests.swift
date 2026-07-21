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
        // "escape" resolves fine, so the earlier assertion exercises the
        // "pane not found" branch specifically. An unresolvable key name
        // must not collapse into the same code (see the dedicated
        // "sendKey reports invalid-key" test below) -- otherwise a typoed
        // key name looks indistinguishable from a stale pane ID.
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

    @Test("sendKey reports invalid-key for an unresolvable key name, even against a known pane")
    func sendKeyReportsInvalidKeyForUnresolvableName() async throws {
        let delegate = StubControlDelegate()
        delegate.knownPaneIDs = ["pane-1"]
        let (server, socketURL) = try await makeServer(delegate: delegate)
        defer { server.stop() }

        // "enter" used to fail as "pane-not-found" even for a pane that
        // exists, because RemoteKeyMapping.namedKeys only had "return" --
        // key-resolution failure and pane-lookup failure collapsed into
        // the same wire error. It must report its own code instead.
        #expect(
            try await perform(
                .sendKey(
                    paneID: "pane-1",
                    key: "not-a-real-key",
                    modifiers: []
                ),
                to: socketURL
            ) == .failure(code: "invalid-key")
        )

        // "enter" is now a documented alias for "return" and must resolve.
        #expect(
            try await perform(
                .sendKey(paneID: "pane-1", key: "enter", modifiers: []),
                to: socketURL
            ) == .ok
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

    // MARK: - agent

    @Test("spawnAgent forwards success and every preflight failure")
    func agentSpawnSuccessAndFailures() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = StubControlAgentDelegate()
        let job = Self.makeJob(state: .launching)
        agentDelegate.spawnResult = .success(job)
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        let response = try await perform(
            .spawnAgent(
                anchorPaneID: "pane-1",
                direction: .right,
                provider: .codex,
                cwd: nil,
                access: .workspaceWrite,
                task: "investigate",
                label: "investigate-a"
            ),
            to: socketURL
        )
        #expect(response == .agentJob(job))
        #expect(agentDelegate.lastSpawnTask == "investigate")
        #expect(agentDelegate.lastSpawnLabel == "investigate-a")

        for code in [
            "pane-not-found",
            "provider-integration-not-installed",
            "provider-integration-needs-repair",
            "invalid-cwd",
            "invalid-label",
            "invalid-task",
        ] {
            agentDelegate.spawnResult = .failure(AgentControlFailure(code))
            let failureResponse = try await perform(
                .spawnAgent(
                    anchorPaneID: "pane-1",
                    direction: .right,
                    provider: .codex,
                    cwd: nil,
                    access: .workspaceWrite,
                    task: "investigate",
                    label: nil
                ),
                to: socketURL
            )
            #expect(failureResponse == .failure(code: code))
        }
    }

    @Test("agent wait resolves once running/attention/completed is reached")
    func agentWaitResolvesOnEachCondition() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = StubControlAgentDelegate()
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        let runningJob = Self.makeJob(state: .running)
        agentDelegate.refreshedSnapshotResult = .success(runningJob)
        let runningResponse = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .running, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        #expect(runningResponse == .agentWaitResult(
            job: runningJob,
            timedOut: false
        ))

        let attentionJob = Self.makeJob(state: .waitingApproval)
        agentDelegate.refreshedSnapshotResult = .success(attentionJob)
        let attentionResponse = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .attention, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        #expect(attentionResponse == .agentWaitResult(
            job: attentionJob,
            timedOut: false
        ))

        let completedJob = Self.makeJob(state: .launchFailed)
        agentDelegate.refreshedSnapshotResult = .success(completedJob)
        let completedResponse = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .completed, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        #expect(completedResponse == .agentWaitResult(
            job: completedJob,
            timedOut: false
        ))
    }

    @Test("agent wait times out when the condition is never satisfied")
    func agentWaitTimesOut() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = StubControlAgentDelegate()
        let launchingJob = Self.makeJob(state: .launching)
        agentDelegate.refreshedSnapshotResult = .success(launchingJob)
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        let response = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .completed, timeoutSeconds: 1),
            to: socketURL,
            timeoutSeconds: 1
        )
        #expect(response == .agentWaitResult(
            job: launchingJob,
            timedOut: true
        ))
    }

    @Test("agent wait fails fast for a missing job")
    func agentWaitFailsForMissingJob() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = StubControlAgentDelegate()
        agentDelegate.refreshedSnapshotResult = .failure(
            AgentControlFailure("job-not-found")
        )
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        let response = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .completed, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        #expect(response == .failure(code: "job-not-found"))
    }

    @Test("agent result returns the job snapshot and pane content")
    func agentResultReturnsSnapshotAndContent() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = StubControlAgentDelegate()
        let job = Self.makeJob(state: .succeeded)
        let content = ControlPaneContent(
            paneID: "pane-1",
            text: "done",
            cursorRow: 0,
            cursorColumn: 0
        )
        agentDelegate.resultContentResult = .success((job, content))
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        let response = try await perform(
            .agentResult(jobID: job.jobID),
            to: socketURL
        )
        #expect(response == .agentResult(job: job, content: content))

        agentDelegate.resultContentResult = .failure(
            AgentControlFailure("job-not-found")
        )
        let missingResponse = try await perform(
            .agentResult(jobID: AgentJobID()),
            to: socketURL
        )
        #expect(missingResponse == .failure(code: "job-not-found"))
    }

    @Test("agent send, focus, and close report success or the delegate's failure")
    func agentSendFocusClose() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = StubControlAgentDelegate()
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        agentDelegate.sendResult = .success(())
        let sendResponse = try await perform(
            .sendAgent(jobID: AgentJobID(), text: "hi", pressEnter: true),
            to: socketURL
        )
        #expect(sendResponse == .ok)
        #expect(agentDelegate.lastSendText == "hi")
        #expect(agentDelegate.lastSendPressEnter == true)

        agentDelegate.focusResult = .success(())
        let focusResponse = try await perform(
            .focusAgent(jobID: AgentJobID()),
            to: socketURL
        )
        #expect(focusResponse == .ok)

        agentDelegate.closeResult = .success(())
        let closeResponse = try await perform(
            .closeAgent(jobID: AgentJobID()),
            to: socketURL
        )
        #expect(closeResponse == .ok)

        // A pane that disappeared must surface as something other than
        // "pane-not-found" through the high-level API.
        agentDelegate.sendResult = .failure(AgentControlFailure("job-lost"))
        let lostResponse = try await perform(
            .sendAgent(jobID: AgentJobID(), text: "hi", pressEnter: false),
            to: socketURL
        )
        #expect(lostResponse == .failure(code: "job-lost"))

        agentDelegate.focusResult = .failure(
            AgentControlFailure("job-not-found")
        )
        let missingResponse = try await perform(
            .focusAgent(jobID: AgentJobID()),
            to: socketURL
        )
        #expect(missingResponse == .failure(code: "job-not-found"))
    }

    /// Reproduces the real bug end to end through the wire protocol: a
    /// job's first run finishes, `agent send` delivers a follow-up, and a
    /// second `agent wait --until completed` must track the *new* run
    /// rather than resolving instantly against the already-terminal one.
    /// `StubControlAgentDelegate` above can't exercise this -- it just
    /// echoes back whatever `Result` the test preset, so it can't tell a
    /// stale run from a fresh one. `FakeAgentJobDelegate` instead wraps a
    /// real `AgentJobTracker` (the same type `AgentJobCoordinator` uses in
    /// the app) so this test actually exercises `prepareForFollowUp`.
    @Test("agent send rebinds a finished job so a follow-up wait doesn't resolve instantly")
    func agentSendRebindsForFollowUpWait() async throws {
        let delegate = StubControlDelegate()
        let agentDelegate = FakeAgentJobDelegate()
        let (server, socketURL) = try await makeServer(
            delegate: delegate,
            agentDelegate: agentDelegate
        )
        defer { server.stop() }

        let firstRun = agentDelegate.addRun(kinds: [
            (.started, Date()),
            (.succeeded, Date()),
        ])

        let firstWait = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .completed, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        guard case let .agentWaitResult(firstJob, firstTimedOut) = firstWait
        else {
            Issue.record("expected agentWaitResult, got \(firstWait)")
            return
        }
        #expect(firstJob.state == .succeeded)
        #expect(firstJob.runID == firstRun.id)
        #expect(!firstTimedOut)

        let sendResponse = try await perform(
            .sendAgent(
                jobID: AgentJobID(),
                text: "one more thing",
                pressEnter: true
            ),
            to: socketURL
        )
        #expect(sendResponse == .ok)

        // No new run has appeared yet -- without the rebind, this would
        // resolve immediately with the *old* job's `.succeeded` state
        // instead of timing out at `.launching`.
        let staleWait = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .completed, timeoutSeconds: 1),
            to: socketURL,
            timeoutSeconds: 1
        )
        guard case let .agentWaitResult(staleJob, staleTimedOut) = staleWait
        else {
            Issue.record("expected agentWaitResult, got \(staleWait)")
            return
        }
        #expect(staleJob.state == .launching)
        #expect(staleTimedOut)

        // Once the follow-up's real run appears, wait tracks that one.
        let secondRun = agentDelegate.addRun(kinds: [
            (.started, Date()),
            (.succeeded, Date()),
        ])
        let secondWait = try await perform(
            .waitAgent(jobID: AgentJobID(), until: .completed, timeoutSeconds: 5),
            to: socketURL,
            timeoutSeconds: 5
        )
        guard case let .agentWaitResult(secondJob, secondTimedOut) = secondWait
        else {
            Issue.record("expected agentWaitResult, got \(secondWait)")
            return
        }
        #expect(secondJob.state == .succeeded)
        #expect(secondJob.runID == secondRun.id)
        #expect(secondJob.runID != firstJob.runID)
        #expect(!secondTimedOut)
    }

    // MARK: - Helpers

    private static func makeJob(
        jobID: AgentJobID = AgentJobID(),
        paneID: TerminalSurfaceID = TerminalSurfaceID(),
        state: AgentJobState
    ) -> AgentJobSnapshot {
        AgentJobSnapshot(
            jobID: jobID,
            paneID: paneID,
            provider: .codex,
            label: "investigate-a",
            state: state,
            runID: nil,
            sessionID: nil,
            message: nil
        )
    }

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
        delegate: StubControlDelegate,
        agentDelegate: ControlServerAgentDelegate? = nil
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
        server.agentDelegate = agentDelegate
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

@MainActor
private final class StubControlAgentDelegate: ControlServerAgentDelegate {
    var spawnResult: Result<AgentJobSnapshot, AgentControlFailure> =
        .failure(AgentControlFailure("job-not-found"))
    var refreshedSnapshotResult: Result<AgentJobSnapshot, AgentControlFailure> =
        .failure(AgentControlFailure("job-not-found"))
    var resultContentResult:
        Result<(AgentJobSnapshot, ControlPaneContent), AgentControlFailure> =
            .failure(AgentControlFailure("job-not-found"))
    var sendResult: Result<Void, AgentControlFailure> =
        .failure(AgentControlFailure("job-not-found"))
    var focusResult: Result<Void, AgentControlFailure> =
        .failure(AgentControlFailure("job-not-found"))
    var closeResult: Result<Void, AgentControlFailure> =
        .failure(AgentControlFailure("job-not-found"))

    var lastSpawnTask: String?
    var lastSpawnLabel: String?
    var lastSendText: String?
    var lastSendPressEnter: Bool?

    func controlServer(
        _ server: ControlServer,
        spawnAgentAnchorPaneID anchorPaneID: String,
        direction: ControlSplitDirection,
        provider: AgentWorkerProvider,
        cwd: String?,
        access: AgentAccessPolicy,
        task: String,
        label: String?
    ) -> Result<AgentJobSnapshot, AgentControlFailure> {
        lastSpawnTask = task
        lastSpawnLabel = label
        return spawnResult
    }

    func controlServer(
        _ server: ControlServer,
        refreshedAgentJobSnapshotForJobID jobID: AgentJobID
    ) -> Result<AgentJobSnapshot, AgentControlFailure> {
        refreshedSnapshotResult
    }

    func controlServer(
        _ server: ControlServer,
        agentResultContentForJobID jobID: AgentJobID
    ) -> Result<(AgentJobSnapshot, ControlPaneContent), AgentControlFailure> {
        resultContentResult
    }

    func controlServer(
        _ server: ControlServer,
        sendAgentText text: String,
        pressEnter: Bool,
        toJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        lastSendText = text
        lastSendPressEnter = pressEnter
        return sendResult
    }

    func controlServer(
        _ server: ControlServer,
        focusAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        focusResult
    }

    func controlServer(
        _ server: ControlServer,
        closeAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        closeResult
    }
}

/// Backs `ControlServerAgentDelegate` with a real `AgentJobTracker`
/// instead of canned `Result`s, so `agentSendRebindsForFollowUpWait` can
/// exercise `AgentJobTracker.prepareForFollowUp` through the actual wire
/// protocol -- see that test for why `StubControlAgentDelegate` can't.
/// Ignores `jobID` throughout (single job per instance), same
/// simplification `StubControlAgentDelegate` makes.
@MainActor
private final class FakeAgentJobDelegate: ControlServerAgentDelegate {
    private let paneID = TerminalSurfaceID()
    private var tracker: AgentJobTracker
    private var runs: [AgentRun] = []

    init() {
        tracker = AgentJobTracker(
            paneID: paneID,
            provider: .codex,
            label: nil,
            baselineRunIDs: [],
            createdAt: Date()
        )
    }

    /// Appends a synthetic run for this delegate's pane/provider, built
    /// by replaying the given event kinds through the real reducer --
    /// mirrors `AgentJobTrackerTests.makeRun`.
    @discardableResult
    func addRun(kinds: [(AgentEventKind, Date)]) -> AgentRun {
        let runID = AgentRunID()
        let events = kinds.map { kind, date in
            AgentEvent(
                runID: runID,
                surfaceID: paneID,
                provider: .codex,
                kind: kind,
                occurredAt: date
            )
        }
        let reduced = AgentEventReducer.reduce(events)
        guard let run = reduced[runID] else {
            fatalError("reducer did not produce a run for \(runID)")
        }
        runs.append(run)
        return run
    }

    func controlServer(
        _ server: ControlServer,
        spawnAgentAnchorPaneID anchorPaneID: String,
        direction: ControlSplitDirection,
        provider: AgentWorkerProvider,
        cwd: String?,
        access: AgentAccessPolicy,
        task: String,
        label: String?
    ) -> Result<AgentJobSnapshot, AgentControlFailure> {
        .failure(AgentControlFailure("not-implemented"))
    }

    func controlServer(
        _ server: ControlServer,
        refreshedAgentJobSnapshotForJobID jobID: AgentJobID
    ) -> Result<AgentJobSnapshot, AgentControlFailure> {
        tracker.reconcile(runs: runs, paneExists: true, now: Date())
        return .success(tracker.snapshot)
    }

    func controlServer(
        _ server: ControlServer,
        agentResultContentForJobID jobID: AgentJobID
    ) -> Result<(AgentJobSnapshot, ControlPaneContent), AgentControlFailure> {
        .failure(AgentControlFailure("not-implemented"))
    }

    func controlServer(
        _ server: ControlServer,
        sendAgentText text: String,
        pressEnter: Bool,
        toJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        tracker.reconcile(runs: runs, paneExists: true, now: Date())
        // Mirrors AgentJobCoordinator.controlServer(_:sendAgentText:...):
        // rebind before delivering the follow-up, using every run
        // currently visible as the new baseline.
        tracker.prepareForFollowUp(
            knownRunIDs: Set(runs.map(\.id)),
            now: Date()
        )
        return .success(())
    }

    func controlServer(
        _ server: ControlServer,
        focusAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        .failure(AgentControlFailure("not-implemented"))
    }

    func controlServer(
        _ server: ControlServer,
        closeAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure> {
        .failure(AgentControlFailure("not-implemented"))
    }
}
