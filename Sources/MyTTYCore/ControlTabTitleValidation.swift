import Foundation

/// Validation for tab names that arrive over the control socket
/// (`rename-tab`, `agent spawn --tab-title`). Same shape as the other short
/// free-text fields the socket accepts (labels, status notes): bounded
/// length, no control characters. Leading/trailing whitespace is allowed on
/// the wire because `WindowSession.rename` trims it.
public enum ControlTabTitleValidation {
    public static let maximumScalars = 100

    /// Valid for `rename-tab`. An empty or whitespace-only title is valid:
    /// it clears the manual name, like the GUI's Rename Tab.
    public static func isValid(_ title: String) -> Bool {
        title.unicodeScalars.count <= maximumScalars
            && title.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    /// Valid for `agent spawn --tab-title`, where there is nothing to
    /// clear: the title must name the tab.
    public static func isValidForSpawn(_ title: String) -> Bool {
        isValid(title)
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
