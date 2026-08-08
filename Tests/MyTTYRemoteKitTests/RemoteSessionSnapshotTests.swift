import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemoteSessionSnapshotTests {
    private func pane(_ id: String) -> RemotePane {
        RemotePane(
            id: id,
            title: "Pane \(id)",
            command: "zsh",
            location: "~",
            kind: .terminal,
            isActive: false
        )
    }

    private func snapshot() -> RemoteSessionSnapshot {
        RemoteSessionSnapshot(
            windows: [
                RemoteWindow(
                    id: "w1",
                    tabs: [
                        RemoteTab(
                            id: "t1",
                            title: "First",
                            panes: [pane("p1"), pane("p2")]
                        )
                    ]
                ),
                RemoteWindow(
                    id: "w2",
                    tabs: [
                        RemoteTab(id: "t2", title: "Second", panes: [pane("p3")])
                    ]
                ),
            ]
        )
    }

    /// An Attention push carries only a pane ID, so the client has to be
    /// able to rebuild the window and tab around it to navigate there.
    @Test
    func locatesPaneWithinItsWindowAndTab() {
        #expect(
            snapshot().location(ofPaneID: "p2")
                == RemotePaneLocation(
                    windowID: "w1",
                    tabID: "t1",
                    paneID: "p2"
                )
        )
        #expect(
            snapshot().location(ofPaneID: "p3")
                == RemotePaneLocation(
                    windowID: "w2",
                    tabID: "t2",
                    paneID: "p3"
                )
        )
    }

    /// A pane that closed on the Mac between the push and the tap must
    /// resolve to nothing rather than to some other pane.
    @Test
    func locatesNothingForAnUnknownPane() {
        #expect(snapshot().location(ofPaneID: "gone") == nil)
        #expect(snapshot().location(ofPaneID: "t1") == nil)
        #expect(
            RemoteSessionSnapshot(windows: []).location(ofPaneID: "p1") == nil
        )
    }

    @Test
    func findsWindowByID() {
        #expect(snapshot().window(withID: "w2")?.tabs.count == 1)
        #expect(snapshot().window(withID: "t1") == nil)
    }

    @Test
    func findsTabAcrossWindows() {
        #expect(snapshot().tab(withID: "t2")?.title == "Second")
        #expect(snapshot().tab(withID: "missing") == nil)
    }

    @Test
    func findsPaneAcrossWindowsAndTabs() {
        #expect(snapshot().pane(withID: "p2")?.title == "Pane p2")
        #expect(snapshot().pane(withID: "p3")?.title == "Pane p3")
        #expect(snapshot().pane(withID: "p4") == nil)
    }

    /// A pane names itself through `mytty-ctl status` or its spawn label;
    /// everything else about it is shared with its tab siblings.
    @Test
    func resolvesOnlyANonEmptyName() {
        #expect(pane("p1").resolvedName == nil)
        var named = pane("p1")
        named.name = "Reviewing #209"
        #expect(named.resolvedName == "Reviewing #209")
        named.name = ""
        #expect(named.resolvedName == nil)
    }

    /// The name is optional in both directions: a host older than protocol
    /// version 7 sends no such key, and a nameless pane must not add one.
    @Test
    func decodesAPayloadWithoutAName() throws {
        let legacy = Data("""
        {"id":"p1","title":"First","command":"zsh","location":"~",
         "kind":"terminal","isActive":false}
        """.utf8)
        let decoded = try JSONDecoder().decode(RemotePane.self, from: legacy)
        #expect(decoded.name == nil)
        #expect(decoded.resolvedName == nil)

        var named = pane("p1")
        named.name = "Watching the build"
        let round = try JSONDecoder().decode(
            RemotePane.self,
            from: JSONEncoder().encode(named)
        )
        #expect(round.name == "Watching the build")
    }

    @Test
    func emptySnapshotFindsNothing() {
        let empty = RemoteSessionSnapshot(windows: [])
        #expect(empty.window(withID: "w1") == nil)
        #expect(empty.tab(withID: "t1") == nil)
        #expect(empty.pane(withID: "p1") == nil)
    }
}
