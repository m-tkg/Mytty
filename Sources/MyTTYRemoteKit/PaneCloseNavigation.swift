import Foundation

/// What a pane detail view should do about navigation after a snapshot
/// arrives, decided platform-neutrally so the rule is testable apart from
/// SwiftUI.
public enum PaneClosePopAction: Equatable, Sendable {
    /// The pane is still in the snapshot; stay put.
    case none
    /// The pane closed but its tab is still open: the pane view pops
    /// itself back to the pane list.
    case popToPaneList
    /// The whole tab closed. The pane view must NOT pop itself: the pane
    /// list dismisses itself for the vanished tab — which also removes
    /// everything above it — and two views editing the navigation path in
    /// the same update race, leaving the stack one level short.
    case deferToTabList
}

public extension RemoteSessionSnapshot {
    /// `tabID` is the tab the pane belonged to when the view appeared;
    /// nil when the owner was never resolved, which keeps the old
    /// pop-yourself behavior as the fallback.
    func paneClosePopAction(
        paneID: String,
        tabID: String?
    ) -> PaneClosePopAction {
        if pane(withID: paneID) != nil { return .none }
        guard let tabID else { return .popToPaneList }
        return tab(withID: tabID) == nil ? .deferToTabList : .popToPaneList
    }
}
