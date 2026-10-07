import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Agent event server", .serialized)
struct AgentEventServerTests {
    @Test("accepts authorized events and rejects revoked capabilities for providers other than Codex")
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
            inheritedSearchPath: "/usr/bin:/bin",
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
        #expect(
            environment[AgentEventServer.searchPathEnvironmentKey]
                == "/usr/bin:/bin:\(directory.path)"
        )
        let optionalStartedDelivery = try AgentHookBridge.makeDelivery(
            provider: .claudeCode,
            payload: Data(
                """
                {
                  "session_id": "claude-session",
                  "prompt_id": "claude-prompt",
                  "hook_event_name": "UserPromptSubmit"
                }
                """.utf8
            ),
            environment: environment,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let startedDelivery = try #require(optionalStartedDelivery)
        let optionalApprovalDelivery = try AgentHookBridge.makeDelivery(
            provider: .claudeCode,
            payload: Data(
                """
                {
                  "session_id": "claude-session",
                  "prompt_id": "claude-prompt",
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
            provider: .claudeCode,
            payload: Data(
                """
                {
                  "session_id": "claude-session",
                  "prompt_id": "claude-prompt",
                  "hook_event_name": "PostToolBatch",
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

    // MARK: - Codex routing by session

    private final class Probe {
        var delivered: [AgentEvent] = []
        var resolverCalls: [AgentEvent] = []
        var resolution: TerminalSurfaceID?
    }

    @MainActor
    private func response(
        for envelope: AgentEventEnvelope,
        resolution: TerminalSurfaceID?
    ) async throws -> (AgentEventServerResponse, Probe) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("mytty.sock")
        let probe = Probe()
        probe.resolution = resolution
        let server = AgentEventServer(
            socketURL: socket,
            aiControlSocketURL: directory.appendingPathComponent("ctl.sock"),
            aiControlExecutableURL: directory
                .appendingPathComponent("mytty-ctl"),
            inheritedSearchPath: "/usr/bin:/bin",
            resolveCodexSurface: { event in
                probe.resolverCalls.append(event)
                return probe.resolution
            },
            onEvent: { event in
                probe.delivered.append(event)
                return true
            },
            onError: { _ in }
        )
        try server.start()
        defer { server.stop() }
        try await waitForSocket(socket)
        let client = AgentEventSocketClient()
        let reply = try await Task.detached {
            try client.send(envelope, to: socket)
        }.value
        return (reply, probe)
    }

    private func sessionEvent(
        provider: AgentProvider,
        surfaceID: TerminalSurfaceID,
        sessionID: String? = "session-1"
    ) -> AgentEvent {
        AgentEvent(
            runID: AgentRunID(),
            sessionID: sessionID,
            surfaceID: surfaceID,
            provider: provider,
            kind: .running,
            occurredAt: Date()
        )
    }

    @Test("delivers a Codex event with a revoked capability to the resolved pane")
    @MainActor
    func codexRoutedBySession() async throws {
        let paneA = TerminalSurfaceID()
        let paneB = TerminalSurfaceID()
        let (reply, probe) = try await response(
            for: AgentEventEnvelope(
                capability: "revoked",
                event: sessionEvent(provider: .codex, surfaceID: paneA)
            ),
            resolution: paneB
        )

        #expect(reply.ok)
        #expect(probe.delivered.map(\.surfaceID) == [paneB])
    }

    @Test("a still-valid capability for another pane does not override the session")
    @MainActor
    func codexIgnoresValidCapability() async throws {
        let paneA = TerminalSurfaceID()
        let paneB = TerminalSurfaceID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("mytty.sock")
        var delivered: [AgentEvent] = []
        let server = AgentEventServer(
            socketURL: socket,
            aiControlSocketURL: directory.appendingPathComponent("ctl.sock"),
            aiControlExecutableURL: directory
                .appendingPathComponent("mytty-ctl"),
            inheritedSearchPath: "/usr/bin:/bin",
            resolveCodexSurface: { _ in paneB },
            onEvent: { event in
                delivered.append(event)
                return true
            },
            onError: { _ in }
        )
        try server.start()
        defer { server.stop() }
        try await waitForSocket(socket)
        let capability = try #require(
            server.environment(for: paneA)[
                AgentEventServer.capabilityEnvironmentKey
            ]
        )
        let envelope = AgentEventEnvelope(
            capability: capability,
            event: sessionEvent(provider: .codex, surfaceID: paneA)
        )
        let client = AgentEventSocketClient()
        let reply = try await Task.detached {
            try client.send(envelope, to: socket)
        }.value

        #expect(reply.ok)
        #expect(delivered.map(\.surfaceID) == [paneB])
    }

    @Test("delivers a Codex event that carries an empty capability")
    @MainActor
    func codexEmptyCapability() async throws {
        let pane = TerminalSurfaceID()
        let (reply, probe) = try await response(
            for: AgentEventEnvelope(
                capability: "",
                event: sessionEvent(
                    provider: .codex,
                    surfaceID: TerminalSurfaceID(
                        rawValue: UUID(
                            uuidString: "00000000-0000-0000-0000-000000000000"
                        )!
                    )
                )
            ),
            resolution: pane
        )

        #expect(reply.ok)
        #expect(probe.delivered.map(\.surfaceID) == [pane])
    }

    @Test("rejects a Codex event whose session resolves to no pane")
    @MainActor
    func codexUnresolved() async throws {
        let (reply, probe) = try await response(
            for: AgentEventEnvelope(
                capability: "anything",
                event: sessionEvent(
                    provider: .codex, surfaceID: TerminalSurfaceID()
                )
            ),
            resolution: nil
        )

        #expect(!reply.ok)
        #expect(reply.error == "unauthorized")
        #expect(probe.resolverCalls.count == 1)
        #expect(probe.delivered.isEmpty)
    }

    @Test("rejects a Codex event without a session id before resolving")
    @MainActor
    func codexWithoutSession() async throws {
        let (reply, probe) = try await response(
            for: AgentEventEnvelope(
                capability: "",
                event: sessionEvent(
                    provider: .codex, surfaceID: TerminalSurfaceID(),
                    sessionID: nil
                )
            ),
            resolution: TerminalSurfaceID()
        )

        #expect(reply.error == "unauthorized")
        #expect(probe.resolverCalls.isEmpty)
        #expect(probe.delivered.isEmpty)
    }

    @Test("still checks schema versions for Codex events")
    @MainActor
    func codexSchemaVersions() async throws {
        let (envelopeReply, envelopeProbe) = try await response(
            for: AgentEventEnvelope(
                schemaVersion: 99,
                capability: "",
                event: sessionEvent(
                    provider: .codex, surfaceID: TerminalSurfaceID()
                )
            ),
            resolution: TerminalSurfaceID()
        )
        #expect(envelopeReply.error == "unauthorized")
        #expect(envelopeProbe.delivered.isEmpty)

        let oldEvent = AgentEvent(
            schemaVersion: 99,
            runID: AgentRunID(),
            sessionID: "session-1",
            surfaceID: TerminalSurfaceID(),
            provider: .codex,
            kind: .running,
            occurredAt: Date()
        )
        let (eventReply, eventProbe) = try await response(
            for: AgentEventEnvelope(capability: "", event: oldEvent),
            resolution: TerminalSurfaceID()
        )
        #expect(eventReply.error == "unauthorized")
        #expect(eventProbe.delivered.isEmpty)
    }

    @Test("other providers keep the capability check and never consult the resolver")
    @MainActor
    func otherProvidersUnchanged() async throws {
        let pane = TerminalSurfaceID()
        let invalid = try await response(
            for: AgentEventEnvelope(
                capability: "invalid",
                event: sessionEvent(provider: .claudeCode, surfaceID: pane)
            ),
            resolution: TerminalSurfaceID()
        )
        #expect(invalid.0.error == "unauthorized")
        #expect(invalid.1.delivered.isEmpty)
        #expect(invalid.1.resolverCalls.isEmpty)
    }

    @Test("a valid capability with a mismatched surface is still rejected for other providers")
    @MainActor
    func otherProvidersSurfaceMismatch() async throws {
        let pane = TerminalSurfaceID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("mytty.sock")
        var delivered: [AgentEvent] = []
        var resolverCalls = 0
        let server = AgentEventServer(
            socketURL: socket,
            aiControlSocketURL: directory.appendingPathComponent("ctl.sock"),
            aiControlExecutableURL: directory
                .appendingPathComponent("mytty-ctl"),
            inheritedSearchPath: "/usr/bin:/bin",
            resolveCodexSurface: { _ in
                resolverCalls += 1
                return nil
            },
            onEvent: { event in
                delivered.append(event)
                return true
            },
            onError: { _ in }
        )
        try server.start()
        defer { server.stop() }
        try await waitForSocket(socket)
        let capabilityForPane = try #require(
            server.environment(for: pane)[
                AgentEventServer.capabilityEnvironmentKey
            ]
        )
        let client = AgentEventSocketClient()
        let mismatched = AgentEventEnvelope(
            capability: capabilityForPane,
            event: sessionEvent(
                provider: .claudeCode, surfaceID: TerminalSurfaceID()
            )
        )
        let matching = AgentEventEnvelope(
            capability: capabilityForPane,
            event: sessionEvent(provider: .claudeCode, surfaceID: pane)
        )
        let mismatchedReply = try await Task.detached {
            try client.send(mismatched, to: socket)
        }.value
        let matchingReply = try await Task.detached {
            try client.send(matching, to: socket)
        }.value

        #expect(mismatchedReply.error == "unauthorized")
        #expect(matchingReply.ok)
        #expect(delivered.map(\.surfaceID) == [pane])
        #expect(resolverCalls == 0)
    }

    private func event(
        runID: AgentRunID,
        surfaceID: TerminalSurfaceID,
        kind: AgentEventKind
    ) -> AgentEvent {
        AgentEvent(
            runID: runID,
            surfaceID: surfaceID,
            provider: .claudeCode,
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
