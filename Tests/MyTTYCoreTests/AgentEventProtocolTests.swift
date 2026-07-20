import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent event authorization")
struct AgentEventProtocolTests {
    @Test("authorizes only the surface scoped to a capability")
    func surfaceScope() throws {
        let allowedSurface = TerminalSurfaceID(rawValue: makeUUID(1))
        let otherSurface = TerminalSurfaceID(rawValue: makeUUID(2))
        var authorizer = AgentEventAuthorizer()
        try authorizer.register(
            capability: "allowed-capability",
            for: allowedSurface
        )

        let allowed = envelope(
            capability: "allowed-capability",
            surfaceID: allowedSurface
        )
        let wrongSurface = envelope(
            capability: "allowed-capability",
            surfaceID: otherSurface
        )
        let wrongCapability = envelope(
            capability: "unknown-capability",
            surfaceID: allowedSurface
        )

        #expect(try authorizer.authorize(allowed) == allowed.event)
        #expect(throws: AgentEventAuthorizationError.surfaceMismatch) {
            try authorizer.authorize(wrongSurface)
        }
        #expect(throws: AgentEventAuthorizationError.invalidCapability) {
            try authorizer.authorize(wrongCapability)
        }
    }

    @Test("rejects unsupported protocol versions")
    func versions() throws {
        let surfaceID = TerminalSurfaceID(rawValue: makeUUID(3))
        var authorizer = AgentEventAuthorizer()
        try authorizer.register(capability: "capability", for: surfaceID)
        let unsupportedEnvelope = AgentEventEnvelope(
            schemaVersion: 2,
            capability: "capability",
            event: event(surfaceID: surfaceID)
        )
        let unsupportedEvent = AgentEventEnvelope(
            capability: "capability",
            event: AgentEvent(
                schemaVersion: 2,
                runID: AgentRunID(rawValue: makeUUID(4)),
                surfaceID: surfaceID,
                provider: .codex,
                kind: .started,
                occurredAt: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(
            throws: AgentEventAuthorizationError.unsupportedEnvelopeVersion(2)
        ) {
            try authorizer.authorize(unsupportedEnvelope)
        }
        #expect(
            throws: AgentEventAuthorizationError.unsupportedEventVersion(2)
        ) {
            try authorizer.authorize(unsupportedEvent)
        }
    }

    @Test("revokes capabilities when a surface closes")
    func revocation() throws {
        let surfaceID = TerminalSurfaceID(rawValue: makeUUID(5))
        let request = envelope(
            capability: "temporary-capability",
            surfaceID: surfaceID
        )
        var authorizer = AgentEventAuthorizer()
        try authorizer.register(
            capability: "temporary-capability",
            for: surfaceID
        )

        authorizer.revoke(surface: surfaceID)

        #expect(throws: AgentEventAuthorizationError.invalidCapability) {
            try authorizer.authorize(request)
        }
    }

    private func envelope(
        capability: String,
        surfaceID: TerminalSurfaceID
    ) -> AgentEventEnvelope {
        AgentEventEnvelope(
            capability: capability,
            event: event(surfaceID: surfaceID)
        )
    }

    private func event(surfaceID: TerminalSurfaceID) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(rawValue: makeUUID(10)),
            runID: AgentRunID(rawValue: makeUUID(11)),
            surfaceID: surfaceID,
            provider: .codex,
            kind: .started,
            occurredAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}
