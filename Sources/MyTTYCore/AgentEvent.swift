import Foundation

public struct AgentEventID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct AgentRunID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum AgentProvider: String, Codable, Equatable, Hashable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case openCode = "opencode"
    case antigravity
    case cursor
}

public enum AgentEventKind: String, Codable, Equatable, Sendable {
    case idle
    case started
    case running
    case inputRequested = "input-requested"
    case approvalRequested = "approval-requested"
    case succeeded
    case failed
    case disconnected
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: AgentEventID
    public let runID: AgentRunID
    public let sessionID: String?
    public let surfaceID: TerminalSurfaceID
    public let provider: AgentProvider
    public let kind: AgentEventKind
    public let occurredAt: Date
    public let message: String?
    /// The provider-specific hook that produced this event (e.g. `Stop`,
    /// `beforeShellExecution`), or a `mytty.`-prefixed marker for events
    /// mytty synthesizes itself. Optional and Codable-default so existing
    /// persisted rows (recorded before this field existed) still decode.
    public let hookName: String?

    public init(
        schemaVersion: Int = AgentEvent.currentSchemaVersion,
        id: AgentEventID = AgentEventID(),
        runID: AgentRunID,
        sessionID: String? = nil,
        surfaceID: TerminalSurfaceID,
        provider: AgentProvider,
        kind: AgentEventKind,
        occurredAt: Date,
        message: String? = nil,
        hookName: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.surfaceID = surfaceID
        self.provider = provider
        self.kind = kind
        self.occurredAt = occurredAt
        self.message = message
        self.hookName = hookName
    }
}

public enum AgentRunState: String, Codable, Equatable, Sendable {
    case unknown
    case idle
    case running
    case waitingInput = "waiting-input"
    case waitingApproval = "waiting-approval"
    case succeeded
    case failed
    case disconnected
}

public struct AgentRun: Equatable, Sendable {
    public let id: AgentRunID
    public fileprivate(set) var sessionID: String?
    public let surfaceID: TerminalSurfaceID
    public let provider: AgentProvider
    public fileprivate(set) var state: AgentRunState
    public fileprivate(set) var startedAt: Date?
    public fileprivate(set) var updatedAt: Date?
    public fileprivate(set) var message: String?
    public fileprivate(set) var acceptedEventCount: Int
}

public enum AgentEventReducer {
    public static func reduce(
        _ events: [AgentEvent]
    ) -> [AgentRunID: AgentRun] {
        AgentEventReplay.replay(events).runs
    }
}

struct AppliedAgentEvent {
    let event: AgentEvent
    let previousState: AgentRunState
    let nextState: AgentRunState
    let startedAt: Date?
}

struct AgentEventReplayResult {
    let runs: [AgentRunID: AgentRun]
    let appliedEvents: [AppliedAgentEvent]
}

enum AgentEventReplay {
    static func replay(_ events: [AgentEvent]) -> AgentEventReplayResult {
        var seenEventIDs = Set<AgentEventID>()
        var runs: [AgentRunID: AgentRun] = [:]
        var appliedEvents: [AppliedAgentEvent] = []

        for event in events {
            guard event.schemaVersion == AgentEvent.currentSchemaVersion,
                  seenEventIDs.insert(event.id).inserted
            else { continue }

            var run = runs[event.runID] ?? AgentRun(
                id: event.runID,
                sessionID: event.sessionID,
                surfaceID: event.surfaceID,
                provider: event.provider,
                state: .unknown,
                startedAt: nil,
                updatedAt: nil,
                message: nil,
                acceptedEventCount: 0
            )
            guard run.surfaceID == event.surfaceID,
                  run.provider == event.provider,
                  run.sessionID == nil || event.sessionID == nil
                    || run.sessionID == event.sessionID
            else { continue }
            if run.sessionID == nil {
                run.sessionID = event.sessionID
            }

            let previousState = run.state
            guard let nextState = transition(
                from: previousState,
                for: event.kind
            ) else {
                runs[event.runID] = run
                continue
            }

            run.state = nextState
            if (previousState == .unknown || previousState == .idle),
               nextState == .running {
                run.startedAt = event.occurredAt
            }
            run.updatedAt = event.occurredAt
            run.message = event.message
            run.acceptedEventCount += 1
            runs[event.runID] = run
            appliedEvents.append(
                AppliedAgentEvent(
                    event: event,
                    previousState: previousState,
                    nextState: nextState,
                    startedAt: run.startedAt
                )
            )
        }

        return AgentEventReplayResult(
            runs: runs,
            appliedEvents: appliedEvents
        )
    }

    private static func transition(
        from state: AgentRunState,
        for kind: AgentEventKind
    ) -> AgentRunState? {
        if kind == .disconnected, state != .disconnected {
            return .disconnected
        }
        if kind == .idle {
            return .idle
        }

        return switch (state, kind) {
        case (.unknown, .started),
             (.unknown, .running),
             (.idle, .started),
             (.idle, .running),
             (.waitingInput, .running),
             (.waitingApproval, .running):
            .running

        case (.running, .inputRequested):
            .waitingInput

        case (.running, .approvalRequested):
            .waitingApproval

        case (.running, .succeeded):
            .succeeded

        case (.running, .failed):
            .failed

        default:
            nil
        }
    }
}
