import Foundation
import MyTTYCore

/// Delegate that turns `ControlRequest`s into actual pane operations.
/// Implemented by `ControlCoordinator`, which has to enumerate every window
/// (a pane ID alone doesn't say which window owns it), the same way
/// `RemoteAccessServerDelegate` does for the iOS remote.
@MainActor
protocol ControlServerDelegate: AnyObject {
    func controlServerListPanes(_ server: ControlServer) -> [ControlPaneInfo]

    func controlServer(
        _ server: ControlServer,
        newTabWithWorkingDirectory workingDirectory: String?,
        command: String?
    ) -> String?

    func controlServer(
        _ server: ControlServer,
        splitPaneID paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?,
        command: String?
    ) -> String?

    func controlServer(
        _ server: ControlServer,
        sendText text: String,
        pressEnter: Bool,
        toPaneID paneID: String
    ) -> Bool

    func controlServer(
        _ server: ControlServer,
        pressKey key: String,
        modifiers: [String],
        toPaneID paneID: String
    ) -> Bool

    func controlServer(
        _ server: ControlServer,
        contentForPaneID paneID: String
    ) -> ControlPaneContent?

    /// The state of the pane's most relevant tracked agent run, or nil if
    /// the pane doesn't exist. Polled by `wait`.
    func controlServer(
        _ server: ControlServer,
        agentStateForPaneID paneID: String
    ) -> AgentRunState??

    func controlServer(
        _ server: ControlServer,
        closePaneID paneID: String
    ) -> Bool

    func controlServer(
        _ server: ControlServer,
        focusPaneID paneID: String
    ) -> Bool
}

/// A `mytty-ctl agent` request that couldn't be completed, carrying the
/// same failure `code` string `ControlResponse.failure` sends over the
/// wire — see `docs/reference/mytty-ctl.md` for the documented codes
/// (`job-not-found`, `provider-integration-not-installed`, etc).
struct AgentControlFailure: Error, Equatable, Sendable {
    let code: String

    init(_ code: String) {
        self.code = code
    }
}

/// Delegate for the `mytty-ctl agent` high-level orchestration API,
/// implemented by `AgentJobCoordinator` (via `ControlCoordinator`). Split
/// out from `ControlServerDelegate` rather than folded into it: the two
/// protocols are resolved by different owners in practice (pane operations
/// resolve straight to a `TerminalWindowController`; agent operations go
/// through job-tracking state first), and keeping them separate keeps each
/// protocol's test stub small — see
/// `docs/explanation/mytty-ctl-architecture.md`.
@MainActor
protocol ControlServerAgentDelegate: AnyObject {
    func controlServer(
        _ server: ControlServer,
        spawnAgentAnchorPaneID anchorPaneID: String,
        direction: ControlSplitDirection,
        provider: AgentWorkerProvider,
        cwd: String?,
        access: AgentAccessPolicy,
        model: String?,
        task: String,
        label: String?
    ) -> Result<AgentJobSnapshot, AgentControlFailure>

    /// Re-reads the job's tracked state against a fresh `AttentionCenter`
    /// snapshot and returns the result — used both to answer `agent
    /// result` and to poll during `agent wait`, so every reply reflects
    /// the job's *current* state rather than whatever it was at spawn.
    func controlServer(
        _ server: ControlServer,
        refreshedAgentJobSnapshotForJobID jobID: AgentJobID
    ) -> Result<AgentJobSnapshot, AgentControlFailure>

    func controlServer(
        _ server: ControlServer,
        agentResultContentForJobID jobID: AgentJobID
    ) -> Result<(AgentJobSnapshot, ControlPaneContent), AgentControlFailure>

    func controlServer(
        _ server: ControlServer,
        sendAgentText text: String,
        pressEnter: Bool,
        toJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure>

    func controlServer(
        _ server: ControlServer,
        focusAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure>

    func controlServer(
        _ server: ControlServer,
        closeAgentJobID jobID: AgentJobID
    ) -> Result<Void, AgentControlFailure>
}

/// Local control server for `mytty-ctl`: the AI-facing counterpart to
/// `RemoteAccessServer`. One JSON request per connection over a
/// user-only Unix socket (`ApplicationPaths.aiControlSocket`) — no
/// pairing/encryption, since the socket file permissions already restrict
/// it to the same local user who could otherwise drive Mytty directly via
/// CGEvent. See `docs/reference/mytty-ctl.md`.
@MainActor
final class ControlServer {
    private static let pollInterval: UInt64 = 300_000_000 // 300ms

    weak var delegate: ControlServerDelegate?
    weak var agentDelegate: ControlServerAgentDelegate?

    private let socketURL: URL
    private let onError: (Error) -> Void
    private var transport: UnixSocketTransport?

    init(socketURL: URL, onError: @escaping (Error) -> Void) {
        self.socketURL = socketURL
        self.onError = onError
    }

    func start() throws {
        stop()
        let transport = UnixSocketTransport(
            socketURL: socketURL,
            label: "dev.mytty.control",
            onRequest: { [weak self] request, reply in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let response = await self.process(request)
                    reply(Self.encode(response))
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.onError(error)
                }
            }
        )
        try transport.start()
        self.transport = transport
    }

    func stop() {
        transport?.stop()
        transport = nil
    }

    private func process(_ requestData: Data?) async -> ControlResponse {
        guard let requestData,
              let request: ControlRequest = try? ControlMessageCodec.decode(
                  requestData
              )
        else {
            return .failure(code: "invalid-request")
        }

        if isAgentRequest(request) {
            guard let agentDelegate else {
                return .failure(code: "not-ready")
            }
            return await processAgent(request, delegate: agentDelegate)
        }

        guard let delegate else {
            return .failure(code: "not-ready")
        }

        switch request {
        case .list:
            return .list(panes: delegate.controlServerListPanes(self))

        case let .newTab(workingDirectory, command):
            guard let paneID = delegate.controlServer(
                self,
                newTabWithWorkingDirectory: workingDirectory,
                command: command
            ) else {
                return .failure(code: "new-tab-failed")
            }
            return .pane(paneID: paneID)

        case let .split(paneID, direction, workingDirectory, command):
            guard let newPaneID = delegate.controlServer(
                self,
                splitPaneID: paneID,
                direction: direction,
                workingDirectory: workingDirectory,
                command: command
            ) else {
                return .failure(code: "split-failed")
            }
            return .pane(paneID: newPaneID)

        case let .send(paneID, text, pressEnter):
            guard delegate.controlServer(
                self,
                sendText: text,
                pressEnter: pressEnter,
                toPaneID: paneID
            ) else {
                return .failure(code: "pane-not-found")
            }
            return .ok

        case let .sendKey(paneID, key, modifiers):
            // Resolve the key name before touching the delegate so an
            // unrecognized name (e.g. "enter" before it was added as a
            // `return` alias) reports as its own failure instead of
            // collapsing into "pane-not-found" — that used to send
            // callers hunting for a pane bug when the pane was fine and
            // the key name was the problem.
            guard RemoteKeyMapping.event(
                key: key,
                modifiers: modifiers
            ) != nil else {
                return .failure(code: "invalid-key")
            }
            guard delegate.controlServer(
                self,
                pressKey: key,
                modifiers: modifiers,
                toPaneID: paneID
            ) else {
                return .failure(code: "pane-not-found")
            }
            return .ok

        case let .read(paneID):
            guard let content = delegate.controlServer(
                self,
                contentForPaneID: paneID
            ) else {
                return .failure(code: "pane-not-found")
            }
            return .content(content)

        case let .wait(paneID, until, timeoutSeconds):
            return await wait(
                for: paneID,
                until: until,
                timeoutSeconds: timeoutSeconds,
                delegate: delegate
            )

        case let .closePane(paneID):
            guard delegate.controlServer(self, closePaneID: paneID) else {
                return .failure(code: "pane-not-found")
            }
            return .ok

        case let .focus(paneID):
            guard delegate.controlServer(self, focusPaneID: paneID) else {
                return .failure(code: "pane-not-found")
            }
            return .ok

        case .spawnAgent, .waitAgent, .agentResult, .sendAgent, .focusAgent,
             .closeAgent:
            // Routed to `processAgent` before this switch is reached — see
            // `isAgentRequest`. Kept here only so the switch stays
            // exhaustive against future `ControlRequest` cases.
            return .failure(code: "invalid-request")
        }
    }

    private func isAgentRequest(_ request: ControlRequest) -> Bool {
        switch request {
        case .spawnAgent, .waitAgent, .agentResult, .sendAgent, .focusAgent,
             .closeAgent:
            true
        default:
            false
        }
    }

    private func processAgent(
        _ request: ControlRequest,
        delegate: ControlServerAgentDelegate
    ) async -> ControlResponse {
        switch request {
        case let .spawnAgent(
            anchorPaneID, direction, provider, cwd, access, model, task, label
        ):
            return Self.encodeAgentResult(
                delegate.controlServer(
                    self,
                    spawnAgentAnchorPaneID: anchorPaneID,
                    direction: direction,
                    provider: provider,
                    cwd: cwd,
                    access: access,
                    model: model,
                    task: task,
                    label: label
                )
            ) { .agentJob($0) }

        case let .waitAgent(jobID, until, timeoutSeconds):
            return await waitAgent(
                jobID: jobID,
                until: until,
                timeoutSeconds: timeoutSeconds,
                delegate: delegate
            )

        case let .agentResult(jobID):
            return Self.encodeAgentResult(
                delegate.controlServer(
                    self,
                    agentResultContentForJobID: jobID
                )
            ) { .agentResult(job: $0.0, content: $0.1) }

        case let .sendAgent(jobID, text, pressEnter):
            return Self.encodeAgentResult(
                delegate.controlServer(
                    self,
                    sendAgentText: text,
                    pressEnter: pressEnter,
                    toJobID: jobID
                )
            ) { _ in .ok }

        case let .focusAgent(jobID):
            return Self.encodeAgentResult(
                delegate.controlServer(self, focusAgentJobID: jobID)
            ) { _ in .ok }

        case let .closeAgent(jobID):
            return Self.encodeAgentResult(
                delegate.controlServer(self, closeAgentJobID: jobID)
            ) { _ in .ok }

        default:
            return .failure(code: "invalid-request")
        }
    }

    private static func encodeAgentResult<Success>(
        _ result: Result<Success, AgentControlFailure>,
        _ transform: (Success) -> ControlResponse
    ) -> ControlResponse {
        switch result {
        case let .success(value):
            transform(value)
        case let .failure(failure):
            .failure(code: failure.code)
        }
    }

    private func waitAgent(
        jobID: AgentJobID,
        until condition: AgentWaitCondition,
        timeoutSeconds: Double,
        delegate: ControlServerAgentDelegate
    ) async -> ControlResponse {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        while true {
            switch delegate.controlServer(
                self,
                refreshedAgentJobSnapshotForJobID: jobID
            ) {
            case let .success(job):
                if job.state.satisfies(condition) {
                    return .agentWaitResult(job: job, timedOut: false)
                }
                if Date() >= deadline {
                    return .agentWaitResult(job: job, timedOut: true)
                }
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            case let .failure(failure):
                return .failure(code: failure.code)
            }
        }
    }

    private func wait(
        for paneID: String,
        until condition: ControlWaitCondition,
        timeoutSeconds: Double,
        delegate: ControlServerDelegate
    ) async -> ControlResponse {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        while true {
            guard let state = delegate.controlServer(
                self,
                agentStateForPaneID: paneID
            ) else {
                return .failure(code: "pane-not-found")
            }
            if Self.satisfies(state, condition) {
                return .waitResult(state: state?.rawValue, timedOut: false)
            }
            if Date() >= deadline {
                return .waitResult(state: state?.rawValue, timedOut: true)
            }
            try? await Task.sleep(nanoseconds: Self.pollInterval)
        }
    }

    private static func satisfies(
        _ state: AgentRunState?,
        _ condition: ControlWaitCondition
    ) -> Bool {
        guard let state else { return false }
        switch condition {
        case .idle:
            return [.idle, .succeeded, .failed, .disconnected]
                .contains(state)
        case .attention:
            return [.waitingInput, .waitingApproval].contains(state)
        }
    }

    private static func encode(_ response: ControlResponse) -> Data {
        var data = (try? ControlMessageCodec.encode(response)) ?? Data()
        data.append(0x0A)
        return data
    }
}
