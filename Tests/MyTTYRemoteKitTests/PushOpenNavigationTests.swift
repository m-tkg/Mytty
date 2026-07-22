import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct PushOpenNavigationTests {
    private func snapshot(windows: [RemoteWindow]) -> RemoteSessionSnapshot {
        RemoteSessionSnapshot(windows: windows, serverProtocolVersion: 3)
    }

    private func pane(_ id: String) -> RemotePane {
        RemotePane(
            id: id,
            title: "title-\(id)",
            command: "zsh",
            location: "~",
            kind: .terminal,
            isActive: false
        )
    }

    /// A single window is shown as its tab list directly, with no window
    /// level in the navigation stack, so the steps must not include one.
    @Test
    func singleWindowSkipsTheWindowStep() {
        let snapshot = snapshot(windows: [
            RemoteWindow(id: "w1", tabs: [
                RemoteTab(id: "t1", title: "Tab", panes: [pane("p1")])
            ])
        ])
        #expect(snapshot.paneOpenSteps(toPaneID: "p1") == [
            .tab(id: "t1"),
            .pane(id: "p1"),
        ])
    }

    @Test
    func multipleWindowsDescendThroughTheOwningWindow() {
        let snapshot = snapshot(windows: [
            RemoteWindow(id: "w1", tabs: [
                RemoteTab(id: "t1", title: "Tab", panes: [pane("p1")])
            ]),
            RemoteWindow(id: "w2", tabs: [
                RemoteTab(id: "t2", title: "Tab", panes: [pane("p2")])
            ]),
        ])
        #expect(snapshot.paneOpenSteps(toPaneID: "p2") == [
            .window(id: "w2"),
            .tab(id: "t2"),
            .pane(id: "p2"),
        ])
    }

    /// The pane named by a push may have been closed on the Mac before the
    /// tap was handled; the caller then falls back to the session root.
    @Test
    func missingPaneYieldsNoSteps() {
        let snapshot = snapshot(windows: [
            RemoteWindow(id: "w1", tabs: [
                RemoteTab(id: "t1", title: "Tab", panes: [pane("p1")])
            ])
        ])
        #expect(snapshot.paneOpenSteps(toPaneID: "gone") == nil)
    }

    @Test
    func connectsWhenNothingIsConnected() {
        #expect(PushOpenConnectPolicy.action(
            targetMacID: "mac-1",
            connectedMacID: nil,
            isConnected: false
        ) == .connect)
    }

    @Test
    func connectsWhenAnotherMacIsConnected() {
        #expect(PushOpenConnectPolicy.action(
            targetMacID: "mac-1",
            connectedMacID: "mac-2",
            isConnected: true
        ) == .connect)
    }

    @Test
    func connectsWhenTheTargetMacIsKnownButDisconnected() {
        #expect(PushOpenConnectPolicy.action(
            targetMacID: "mac-1",
            connectedMacID: "mac-1",
            isConnected: false
        ) == .connect)
    }

    /// A session that still looks alive is reused rather than dropped —
    /// reconnecting would lose the pane content already on screen. But a
    /// connection that survived backgrounding often only reports its death
    /// a moment after the app resumes, so the caller must arm a reconnect
    /// instead of trusting it outright.
    @Test
    func reusesALiveLookingSessionButArmsAReconnect() {
        #expect(PushOpenConnectPolicy.action(
            targetMacID: "mac-1",
            connectedMacID: "mac-1",
            isConnected: true
        ) == .reuseButArmReconnect)
    }
}
