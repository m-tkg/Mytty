import Foundation
import Testing

@testable import MyTTYCore

@Suite("Remote pane state")
struct RemotePaneStateTests {
    private func remote(
        hostID: String = "host-1",
        remotePaneID: String = "pane-1"
    ) -> RemotePaneState {
        RemotePaneState(
            hostID: hostID,
            remotePaneID: remotePaneID,
            hostName: "Studio",
            title: "codex"
        )
    }

    private func terminal() -> TerminalSurfaceState {
        TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
    }

    @Test("a remote pane is a pane but not a surface")
    func remoteIsNotASurface() {
        let state = remote()
        let node = SplitNode.remote(state)
        // Everything that walks *surfaces* — agent event revocation,
        // scrollback capture, close confirmation — must skip a remote pane,
        // which has no Ghostty surface behind it.
        #expect(node.surfaceIDs.isEmpty)
        #expect(node.paneIDs == [state.id])
        #expect(node.remoteState(with: state.id) == state)
        #expect(node.browserState(with: state.id) == nil)
    }

    @Test("splitting adds a remote pane and focuses it")
    func splitAddsRemotePane() throws {
        var tab = TabSession(initialSurface: terminal())
        let state = remote()
        try tab.split(remote: state, direction: .right)

        #expect(tab.paneIDs.count == 2)
        #expect(tab.focusedSurfaceID == state.id)
        #expect(tab.root.remoteState(with: state.id) == state)
        // The terminal beside it is still the tab's only surface.
        #expect(tab.surfaceIDs.count == 1)
    }

    @Test("a tab can start as a remote pane")
    func tabOfOnlyARemotePane() {
        let state = remote()
        let tab = TabSession(initialRemote: state)
        #expect(tab.focusedSurfaceID == state.id)
        #expect(tab.paneIDs == [state.id])
        #expect(tab.surfaceIDs.isEmpty)
    }

    @Test("closing a remote pane leaves the rest of the layout")
    func closingRemotePane() throws {
        var tab = TabSession(initialSurface: terminal())
        let state = remote()
        try tab.split(remote: state, direction: .right)
        try tab.close(pane: state.id)

        #expect(tab.paneIDs.count == 1)
        #expect(tab.root.remoteState(with: state.id) == nil)
    }

    @Test("records the title the host reported")
    func updateRemoteTitle() throws {
        var tab = TabSession(initialRemote: remote())
        let paneID = tab.focusedSurfaceID
        try tab.updateRemoteTitle("claude", for: paneID)
        #expect(tab.root.remoteState(with: paneID)?.title == "claude")
    }

    @Test("updating the title of a pane that is not remote throws")
    func updateRemoteTitleOnWrongKind() {
        var tab = TabSession(initialSurface: terminal())
        let paneID = tab.focusedSurfaceID
        #expect(throws: TabSessionError.surfaceNotFound(paneID)) {
            try tab.updateRemoteTitle("x", for: paneID)
        }
    }

    @Test("reopening a tab gives its remote panes fresh ids")
    func regeneratingIDs() throws {
        var tab = TabSession(initialSurface: terminal())
        let state = remote()
        try tab.split(remote: state, direction: .right)

        let reopened = tab.regeneratingIDs()
        let regenerated = reopened.root.remoteStates.first
        #expect(regenerated != nil)
        #expect(regenerated?.id != state.id)
        // Everything that identifies *what* it mirrors survives the
        // renumbering; only the local pane id changes.
        #expect(regenerated?.hostID == state.hostID)
        #expect(regenerated?.remotePaneID == state.remotePaneID)
        #expect(regenerated?.hostName == state.hostName)
    }

    @Test("survives a session encode/decode round trip")
    func codableRoundTrip() throws {
        var tab = TabSession(initialSurface: terminal())
        let state = remote()
        try tab.split(remote: state, direction: .down)

        let data = try JSONEncoder().encode(tab.root)
        let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
        #expect(decoded.remoteState(with: state.id) == state)
    }

    @Test("a remote pane takes an equal share when panes are equalized")
    func equalize() throws {
        var tab = TabSession(initialSurface: terminal())
        try tab.split(remote: remote(), direction: .right)
        tab.equalizePanes()

        guard case let .split(_, ratio, _, _) = tab.root else {
            Issue.record("expected a split root")
            return
        }
        #expect(abs(ratio - 0.5) < 0.0001)
    }
}

private extension SplitNode {
    var remoteStates: [RemotePaneState] {
        switch self {
        case .surface, .browser:
            []
        case let .remote(state):
            [state]
        case let .split(_, _, first, second):
            first.remoteStates + second.remoteStates
        }
    }
}
