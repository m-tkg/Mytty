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
        newTabWithWorkingDirectory workingDirectory: String?
    ) -> String?

    func controlServer(
        _ server: ControlServer,
        splitPaneID paneID: String,
        direction: ControlSplitDirection,
        workingDirectory: String?
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
        guard let delegate else {
            return .failure(code: "not-ready")
        }

        switch request {
        case .list:
            return .list(panes: delegate.controlServerListPanes(self))

        case let .newTab(workingDirectory):
            guard let paneID = delegate.controlServer(
                self,
                newTabWithWorkingDirectory: workingDirectory
            ) else {
                return .failure(code: "new-tab-failed")
            }
            return .pane(paneID: paneID)

        case let .split(paneID, direction, workingDirectory):
            guard let newPaneID = delegate.controlServer(
                self,
                splitPaneID: paneID,
                direction: direction,
                workingDirectory: workingDirectory
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
