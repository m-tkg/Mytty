import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

@Suite("Remote pane picker")
struct RemotePanePickerTests {
    private func mac(_ id: String) -> PairedMac {
        PairedMac(
            deviceID: id,
            deviceSecretBase64: "",
            macName: "\(id)-service",
            displayName: id
        )
    }

    @Test("a preselected Mac wins over the default first host")
    func preselectedHostWins() {
        let hosts = [mac("desktop"), mac("studio")]
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: "studio",
                hosts: hosts
            ) == "studio"
        )
    }

    @Test("no preselection falls back to the first host")
    func fallsBackToFirstHost() {
        let hosts = [mac("desktop"), mac("studio")]
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: nil,
                hosts: hosts
            ) == "desktop"
        )
    }

    private func pane(_ id: String, name: String? = nil) -> RemotePane {
        RemotePane(
            id: id,
            title: "mytty",
            command: "zsh",
            location: "~/git/mytty",
            kind: .terminal,
            isActive: false,
            name: name
        )
    }

    @Test("groups a host's panes under the tab they belong to")
    func groupsPanesByTab() {
        let snapshot = RemoteSessionSnapshot(windows: [
            RemoteWindow(id: "w1", tabs: [
                RemoteTab(id: "t1", title: "mytty", panes: [
                    pane("p1", name: "Reviewing #209"),
                    pane("p2"),
                ]),
                RemoteTab(id: "t2", title: "otegami", panes: [pane("p3")]),
            ]),
            RemoteWindow(id: "w2", tabs: [
                RemoteTab(id: "t3", title: "notes", panes: [pane("p4")]),
            ]),
        ])

        let groups = RemotePanePickerGroup.groups(in: snapshot)

        #expect(groups.map(\.id) == ["t1", "t2", "t3"])
        #expect(groups.map(\.title) == ["mytty", "otegami", "notes"])
        #expect(groups[0].panes.map(\.id) == ["p1", "p2"])
        // Only the first pane named itself; the other falls back to the
        // section's tab title, which is all the host knows about it.
        #expect(groups[0].panes[0].resolvedName == "Reviewing #209")
        #expect(groups[0].panes[1].resolvedName == nil)
    }

    @Test("drops a tab with no offerable panes")
    func dropsEmptyTabs() {
        let snapshot = RemoteSessionSnapshot(windows: [
            RemoteWindow(id: "w1", tabs: [
                // Every pane of this tab already mirrors a third Mac, so the
                // host offered none of them.
                RemoteTab(id: "t1", title: "mirrors", panes: []),
                RemoteTab(id: "t2", title: "mytty", panes: [pane("p1")]),
            ]),
        ])

        #expect(RemotePanePickerGroup.groups(in: snapshot).map(\.id) == ["t2"])
        #expect(
            RemotePanePickerGroup.groups(
                in: RemoteSessionSnapshot(windows: [])
            )
            .isEmpty
        )
    }

    @Test("a stale preselection is ignored, not selected blindly")
    func ignoresUnknownPreselection() {
        let hosts = [mac("desktop")]
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: "unpaired",
                hosts: hosts
            ) == "desktop"
        )
        #expect(
            RemotePanePickerModel.initialHostID(
                preselected: "unpaired",
                hosts: []
            ) == nil
        )
    }
}
