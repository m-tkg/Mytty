import Foundation
import MyTTYCore

/// Shared `--direction auto` resolution for `mytty-ctl split` and `agent
/// spawn`: finds the tab containing the anchor pane and asks
/// `BalancedPaneInsertion` which existing pane to split next to (which
/// may differ from the anchor itself) and in which direction, so a team
/// of spawned workers grows as a near-square grid instead of a 1×N
/// strip. Both `ControlCoordinator.splitPaneID` and
/// `AgentJobCoordinator.spawnAgentAnchorPaneID` resolve through this
/// before mapping `ControlSplitDirection` to `SplitDirection`.
@MainActor
enum BalancedSplitResolution {
    /// `direction` is the raw wire value. `.auto` resolves via
    /// `BalancedPaneInsertion` against the tab containing
    /// `anchorPaneID`; any other value is honored as-is against
    /// `anchorPaneID` unchanged. Falls back to splitting `anchorPaneID`
    /// itself `.right` when its containing tab can't be found or the
    /// algorithm returns nil for a non-empty tab (shouldn't happen).
    static func resolve(
        direction: ControlSplitDirection,
        anchorPaneID: TerminalSurfaceID,
        controller: TerminalWindowController
    ) -> (paneID: TerminalSurfaceID, direction: SplitDirection) {
        guard direction == .auto else {
            return (
                anchorPaneID,
                SplitDirection(rawValue: direction.rawValue) ?? .right
            )
        }
        guard let tab = controller.session.tabs.first(where: {
            $0.paneIDs.contains(anchorPaneID)
        }), let target = BalancedPaneInsertion.target(
            in: tab.root,
            containerAspectRatio: controller.paneContainerAspectRatio()
        ) else {
            return (anchorPaneID, .right)
        }
        return target
    }
}
