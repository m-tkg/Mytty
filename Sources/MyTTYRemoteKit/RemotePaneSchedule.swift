import Foundation

/// Wire representation of a Mac-side pane input schedule. `id` is the
/// Mac-side schedule UUID string.
public struct RemotePaneSchedule: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var fireAt: Date
    public var text: String
    public var pressEnter: Bool

    public init(
        id: String,
        fireAt: Date,
        text: String,
        pressEnter: Bool
    ) {
        self.id = id
        self.fireAt = fireAt
        self.text = text
        self.pressEnter = pressEnter
    }
}
