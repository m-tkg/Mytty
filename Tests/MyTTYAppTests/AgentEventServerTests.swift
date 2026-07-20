import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Agent event server", .serialized)
struct AgentEventServerTests {
    @Test("accepts authorized events and rejects revoked capabilities")
    @MainActor
    func authorizationOverUnixSocket() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let socket = directory.appendingPathComponent("mytty.sock")
        let controlSocket = directory.appendingPathComponent(
            "mytty-ctl.sock"
        )
        let repository = SQLiteAgentEventRepository(
            databaseURL: directory.appendingPathComponent("mytty.sqlite")
        )
        let center = AttentionCenter(repository: repository)
        var serverErrors: [String] = []
        let server = AgentEventServer(
            socketURL: socket,
            aiControlSocketURL: controlSocket,
            aiControlExecutableURL: directory
                .appendingPathComponent("mytty-ctl"),
            onEvent: { event in try center.append(event) },
            onError: { serverErrors.append(String(describing: $0)) }
        )
        try server.start()
        defer { server.stop() }
        try await waitForSocket(socket)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: socket.path
        )
        #expect(attributes[.posixPermissions] as? Int == 0o600)

        let surfaceID = TerminalSurfaceID()
        let environment = try server.environment(for: surfaceID)
        let capability = try #require(
            environment[AgentEventServer.capabilityEnvironmentKey]
        )
        let optionalStartedDelivery = try AgentHookBridge.makeDelivery(
            provider: .codex,
            payload: Data(
                """
                {
                  "session_id": "codex-session",
                  "turn_id": "codex-turn",
                  "hook_event_name": "UserPromptSubmit"
                }
                """.utf8
            ),
            environment: environment,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let startedDelivery = try #require(optionalStartedDelivery)
        let optionalApprovalDelivery = try AgentHookBridge.makeDelivery(
            provider: .codex,
            payload: Data(
                """
                {
                  "session_id": "codex-session",
                  "turn_id": "codex-turn",
                  "hook_event_name": "PermissionRequest",
                  "tool_name": "Bash"
                }
                """.utf8
            ),
            environment: environment,
            occurredAt: Date(timeIntervalSince1970: 101)
        )
        let approvalDelivery = try #require(optionalApprovalDelivery)
        let optionalRunningDelivery = try AgentHookBridge.makeDelivery(
            provider: .codex,
            payload: Data(
                """
                {
                  "session_id": "codex-session",
                  "turn_id": "codex-turn",
                  "hook_event_name": "PostToolUse",
                  "tool_name": "Bash"
                }
                """.utf8
            ),
            environment: environment,
            occurredAt: Date(timeIntervalSince1970: 102)
        )
        let runningDelivery = try #require(optionalRunningDelivery)
        let started = startedDelivery.envelope.event
        let approval = approvalDelivery.envelope.event
        let running = runningDelivery.envelope.event
        let runID = started.runID

        let client = AgentEventSocketClient()
        let startedResponse = try await Task.detached {
            try client.send(
                startedDelivery.envelope,
                to: startedDelivery.socketURL
            )
        }.value
        let approvalResponse = try await Task.detached {
            try client.send(
                approvalDelivery.envelope,
                to: approvalDelivery.socketURL
            )
        }.value

        #expect(startedResponse.ok)
        #expect(approvalResponse.ok)
        #expect(center.actionableCount == 1)
        let runningResponse = try await Task.detached {
            try client.send(
                runningDelivery.envelope,
                to: runningDelivery.socketURL
            )
        }.value
        #expect(runningResponse.ok)
        #expect(center.actionableCount == 0)
        var storedEvents = try repository.loadEvents()
        #expect(storedEvents.map(\.id) == [started.id, approval.id, running.id])
        #expect(storedEvents.map(\.kind) == [
            .started,
            .approvalRequested,
            .running,
        ])

        let unauthorizedResponse = try await Task.detached {
            try client.send(
                AgentEventEnvelope(
                    capability: "invalid",
                    event: event(
                        runID: runID,
                        surfaceID: surfaceID,
                        kind: .running
                    )
                ),
                to: socket
            )
        }.value
        #expect(!unauthorizedResponse.ok)
        #expect(unauthorizedResponse.error == "unauthorized")

        server.revoke(surface: surfaceID)
        let revokedResponse = try await Task.detached {
            try client.send(
                AgentEventEnvelope(
                    capability: capability,
                    event: event(
                        runID: runID,
                        surfaceID: surfaceID,
                        kind: .running
                    )
                ),
                to: socket
            )
        }.value
        #expect(!revokedResponse.ok)
        storedEvents = try repository.loadEvents()
        #expect(storedEvents.map(\.id) == [started.id, approval.id, running.id])
        #expect(serverErrors.isEmpty)
    }

    private func event(
        runID: AgentRunID,
        surfaceID: TerminalSurfaceID,
        kind: AgentEventKind
    ) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .codex,
            kind: kind,
            occurredAt: Date()
        )
    }

    @MainActor
    private func waitForSocket(_ socket: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: socket.path) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ServerTestError.socketDidNotStart
    }

}

private enum ServerTestError: Error {
    case socketDidNotStart
}
