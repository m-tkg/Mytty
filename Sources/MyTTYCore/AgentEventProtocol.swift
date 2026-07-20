import Foundation

public struct AgentEventEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let capability: String
    public let event: AgentEvent

    public init(
        schemaVersion: Int = AgentEventEnvelope.currentSchemaVersion,
        capability: String,
        event: AgentEvent
    ) {
        self.schemaVersion = schemaVersion
        self.capability = capability
        self.event = event
    }
}

public enum AgentEventAuthorizationError: Error, Equatable, Sendable {
    case emptyCapability
    case duplicateCapability
    case invalidCapability
    case surfaceMismatch
    case unsupportedEnvelopeVersion(Int)
    case unsupportedEventVersion(Int)
}

public struct AgentEventAuthorizer: Sendable {
    private var surfaceByCapability: [String: TerminalSurfaceID] = [:]

    public init() {}

    public mutating func register(
        capability: String,
        for surfaceID: TerminalSurfaceID
    ) throws {
        guard !capability.isEmpty else {
            throw AgentEventAuthorizationError.emptyCapability
        }
        if let existing = surfaceByCapability[capability],
           existing != surfaceID {
            throw AgentEventAuthorizationError.duplicateCapability
        }
        surfaceByCapability[capability] = surfaceID
    }

    public mutating func revoke(surface surfaceID: TerminalSurfaceID) {
        surfaceByCapability = surfaceByCapability.filter {
            $0.value != surfaceID
        }
    }

    public func authorize(_ envelope: AgentEventEnvelope) throws -> AgentEvent {
        guard envelope.schemaVersion
                == AgentEventEnvelope.currentSchemaVersion
        else {
            throw AgentEventAuthorizationError.unsupportedEnvelopeVersion(
                envelope.schemaVersion
            )
        }
        guard envelope.event.schemaVersion
                == AgentEvent.currentSchemaVersion
        else {
            throw AgentEventAuthorizationError.unsupportedEventVersion(
                envelope.event.schemaVersion
            )
        }
        guard let surfaceID = surfaceByCapability[envelope.capability] else {
            throw AgentEventAuthorizationError.invalidCapability
        }
        guard envelope.event.surfaceID == surfaceID else {
            throw AgentEventAuthorizationError.surfaceMismatch
        }
        return envelope.event
    }
}
