import Foundation

/// One level of the navigation stack on the way to a pane, in the order
/// the client pushes them. Kept platform-neutral so the decision of what
/// to push is testable apart from SwiftUI.
public enum PaneOpenStep: Equatable, Sendable {
    case window(id: String)
    case tab(id: String)
    case pane(id: String)
}

public extension RemoteSessionSnapshot {
    /// The full descent to a pane a tapped Attention push names, or nil
    /// when the pane is not in this snapshot (closed on the Mac before
    /// the tap was handled — the caller falls back to the session root).
    ///
    /// A single window is shown as its tab list directly, with no window
    /// level in the navigation stack, so the window step only appears
    /// when there is more than one.
    func paneOpenSteps(toPaneID id: String) -> [PaneOpenStep]? {
        guard let location = location(ofPaneID: id) else { return nil }
        var steps: [PaneOpenStep] = []
        if windows.count > 1 {
            steps.append(.window(id: location.windowID))
        }
        steps.append(.tab(id: location.tabID))
        steps.append(.pane(id: location.paneID))
        return steps
    }
}

/// What to do about the connection when a tapped push targets a Mac.
public enum PushOpenConnectAction: Equatable, Sendable {
    /// Start a fresh connection: nothing usable is up.
    case connect
    /// The target Mac's session still looks alive, so keep it — dropping
    /// it would lose the pane content already mirrored. But a connection
    /// that survived backgrounding often only reports its death a moment
    /// after the app resumes, so the caller must arm its foreground
    /// reconnect rather than trust the session outright.
    case reuseButArmReconnect
}

public enum PushOpenConnectPolicy {
    public static func action(
        targetMacID: String,
        connectedMacID: String?,
        isConnected: Bool
    ) -> PushOpenConnectAction {
        if connectedMacID == targetMacID, isConnected {
            return .reuseButArmReconnect
        }
        return .connect
    }
}
