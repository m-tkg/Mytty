import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct PaneCloseNavigationTests {
    private func snapshot(tabs: [RemoteTab]) -> RemoteSessionSnapshot {
        RemoteSessionSnapshot(windows: [
            RemoteWindow(id: "window-1", tabs: tabs),
        ])
    }

    private func tab(_ id: String, paneIDs: [String]) -> RemoteTab {
        RemoteTab(
            id: id,
            title: id,
            panes: paneIDs.map {
                RemotePane(
                    id: $0,
                    title: $0,
                    command: "zsh",
                    location: "~",
                    kind: .terminal,
                    isActive: false
                )
            }
        )
    }

    @Test
    func stillPresentPaneNeedsNoPop() {
        let snapshot = snapshot(tabs: [tab("tab-1", paneIDs: ["pane-1"])])
        #expect(
            snapshot.paneClosePopAction(paneID: "pane-1", tabID: "tab-1")
                == PaneClosePopAction.none
        )
    }

    @Test
    func closedPaneInLivingTabPopsToPaneList() {
        let snapshot = snapshot(tabs: [tab("tab-1", paneIDs: ["pane-2"])])
        #expect(
            snapshot.paneClosePopAction(paneID: "pane-1", tabID: "tab-1")
                == .popToPaneList
        )
    }

    /// The whole tab closed: the pane view must not pop itself, because
    /// the pane list pops itself (and everything above it) back to the
    /// tab list, and two simultaneous path edits race.
    @Test
    func closedTabDefersToThePaneList() {
        let snapshot = snapshot(tabs: [tab("tab-2", paneIDs: ["pane-9"])])
        #expect(
            snapshot.paneClosePopAction(paneID: "pane-1", tabID: "tab-1")
                == .deferToTabList
        )
    }

    /// Without a known owning tab the pane view keeps its old behavior —
    /// popping itself is the only navigation anyone can do.
    @Test
    func unknownOwningTabFallsBackToPoppingThePaneView() {
        let snapshot = snapshot(tabs: [tab("tab-2", paneIDs: ["pane-9"])])
        #expect(
            snapshot.paneClosePopAction(paneID: "pane-1", tabID: nil)
                == .popToPaneList
        )
    }
}
