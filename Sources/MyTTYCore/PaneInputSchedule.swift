import Foundation

public struct PaneInputScheduleID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct PaneInputSchedule: Codable, Equatable, Identifiable, Sendable {
    public let id: PaneInputScheduleID
    public let surfaceID: TerminalSurfaceID
    public let fireAt: Date
    public let text: String
    public let appendNewline: Bool

    public init(
        id: PaneInputScheduleID = PaneInputScheduleID(),
        surfaceID: TerminalSurfaceID,
        fireAt: Date,
        text: String,
        appendNewline: Bool
    ) {
        self.id = id
        self.surfaceID = surfaceID
        self.fireAt = fireAt
        self.text = text
        self.appendNewline = appendNewline
    }

    public var input: String {
        text + (appendNewline ? "\n" : "")
    }
}
