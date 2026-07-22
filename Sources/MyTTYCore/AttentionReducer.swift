import Foundation

public struct AttentionPolicy: Equatable, Sendable {
    public var resolvedRetention: TimeInterval

    public init(
        resolvedRetention: TimeInterval = 24 * 60 * 60
    ) {
        self.resolvedRetention = resolvedRetention
    }
}

public struct AttentionAcknowledgement: Codable, Equatable, Sendable {
    public let eventID: AgentEventID
    public let acknowledgedAt: Date

    public init(eventID: AgentEventID, acknowledgedAt: Date) {
        self.eventID = eventID
        self.acknowledgedAt = acknowledgedAt
    }
}

public enum AttentionItemKind: String, Codable, Equatable, Sendable {
    case approvalRequest = "approval-request"
    case inputRequest = "input-request"
    case failure
    case disconnected
    case completion
}

public struct AttentionItem: Identifiable, Equatable, Sendable {
    public let id: AgentEventID
    public let runID: AgentRunID
    public let surfaceID: TerminalSurfaceID
    public let provider: AgentProvider
    public let kind: AttentionItemKind
    public let createdAt: Date
    public let message: String?
    public let toolName: String?
    public let resolvedAt: Date?
    public let acknowledgedAt: Date?

    public var isActionable: Bool {
        resolvedAt == nil && acknowledgedAt == nil
    }
}

public enum AttentionReducer {
    public static func reduce(
        events: [AgentEvent],
        acknowledgements: [AttentionAcknowledgement],
        now: Date,
        policy: AttentionPolicy = AttentionPolicy()
    ) -> [AttentionItem] {
        let replay = AgentEventReplay.replay(events)
        let acknowledgementDates = acknowledgementDatesByEventID(
            acknowledgements
        )
        var drafts: [AttentionItemDraft] = []
        var requestIndexByRunID: [AgentRunID: Int] = [:]

        for applied in replay.appliedEvents {
            if applied.previousState == .waitingInput
                || applied.previousState == .waitingApproval {
                if let index = requestIndexByRunID.removeValue(
                    forKey: applied.event.runID
                ) {
                    drafts[index].resolvedAt = applied.event.occurredAt
                }
            }

            guard let kind = attentionKind(
                for: applied,
                policy: policy
            ) else { continue }

            let index = drafts.count
            drafts.append(
                AttentionItemDraft(
                    event: applied.event,
                    kind: kind,
                    resolvedAt: nil
                )
            )
            if kind == .inputRequest || kind == .approvalRequest {
                requestIndexByRunID[applied.event.runID] = index
            }
        }

        return drafts.compactMap { draft in
            let acknowledgedAt = acknowledgementDates[draft.event.id]
            let retentionAnchor = [draft.resolvedAt, acknowledgedAt]
                .compactMap { $0 }
                .min()
            if let retentionAnchor,
               now.timeIntervalSince(retentionAnchor)
                > policy.resolvedRetention {
                return nil
            }

            return AttentionItem(
                id: draft.event.id,
                runID: draft.event.runID,
                surfaceID: draft.event.surfaceID,
                provider: draft.event.provider,
                kind: draft.kind,
                createdAt: draft.event.occurredAt,
                message: draft.event.message,
                toolName: draft.event.toolName,
                resolvedAt: draft.resolvedAt,
                acknowledgedAt: acknowledgedAt
            )
        }
        .sorted { first, second in
            if first.createdAt != second.createdAt {
                return first.createdAt > second.createdAt
            }
            return first.id.rawValue.uuidString > second.id.rawValue.uuidString
        }
    }

    private static func attentionKind(
        for applied: AppliedAgentEvent,
        policy: AttentionPolicy
    ) -> AttentionItemKind? {
        switch applied.event.kind {
        case .inputRequested:
            .inputRequest
        case .approvalRequested:
            .approvalRequest
        case .failed:
            .failure
        case .disconnected:
            nil
        // Every completion surfaces: the app auto-acknowledges items for
        // the actively focused pane on arrival, so this is what tells the
        // user an agent finished in a tab or pane they are not watching.
        case .succeeded:
            .completion
        case .idle,
             .started,
             .running:
            nil
        }
    }

    private static func acknowledgementDatesByEventID(
        _ acknowledgements: [AttentionAcknowledgement]
    ) -> [AgentEventID: Date] {
        var result: [AgentEventID: Date] = [:]
        for acknowledgement in acknowledgements {
            let current = result[acknowledgement.eventID]
            result[acknowledgement.eventID] = min(
                current ?? acknowledgement.acknowledgedAt,
                acknowledgement.acknowledgedAt
            )
        }
        return result
    }
}

private struct AttentionItemDraft {
    let event: AgentEvent
    let kind: AttentionItemKind
    var resolvedAt: Date?
}
