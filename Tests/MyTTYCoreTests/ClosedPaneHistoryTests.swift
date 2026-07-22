import Foundation
import Testing

@testable import MyTTYCore

@Suite("Closed pane history")
struct ClosedPaneHistoryTests {
    @Test("returns entries most-recently-closed first")
    @MainActor
    func lifoOrder() {
        let history = ClosedPaneHistory()
        history.push(.terminal(makeSurface(id: 1, path: "/first")))
        history.push(.terminal(makeSurface(id: 2, path: "/second")))
        history.push(.terminal(makeSurface(id: 3, path: "/third")))

        #expect(history.entries.map(\.record) == [
            .terminal(makeSurface(id: 3, path: "/third")),
            .terminal(makeSurface(id: 2, path: "/second")),
            .terminal(makeSurface(id: 1, path: "/first")),
        ])
    }

    @Test("drops the oldest entry once capacity is exceeded")
    @MainActor
    func capacity() {
        let history = ClosedPaneHistory()
        for index in 1...21 {
            history.push(.terminal(makeSurface(
                id: UInt8(index),
                path: "/pane-\(index)"
            )))
        }

        #expect(history.entries.count == ClosedPaneHistory.capacity)
        #expect(
            history.entries.first?.record
                == .terminal(makeSurface(id: 21, path: "/pane-21"))
        )
        #expect(
            history.entries.last?.record
                == .terminal(makeSurface(id: 2, path: "/pane-2"))
        )
    }

    @Test("removes an entry by id without disturbing the others")
    @MainActor
    func removeByID() {
        let history = ClosedPaneHistory()
        history.push(.terminal(makeSurface(id: 1, path: "/first")))
        history.push(.terminal(makeSurface(id: 2, path: "/second")))
        history.push(.terminal(makeSurface(id: 3, path: "/third")))
        let middle = history.entries[1]

        let removed = history.remove(id: middle.id)

        #expect(removed?.id == middle.id)
        #expect(history.entries.count == 2)
        #expect(!history.entries.contains { $0.id == middle.id })
        #expect(history.remove(id: UUID()) == nil)
    }

    @Test("regenerates IDs on a single-surface tab while keeping history and resume")
    @MainActor
    func regeneratingIDsSingleSurface() {
        var surface = makeSurface(id: 1, path: "/repo")
        surface.terminalHistory = "hello"
        surface.agentResume = AgentResumeDescriptor(
            kind: .codex,
            sessionID: "session-1"
        )
        let tab = TabSession(id: makeTabID(1), initialSurface: surface)

        let restored = tab.regeneratingIDs()

        #expect(restored.id != tab.id)
        #expect(restored.paneIDs.count == 1)
        #expect(restored.paneIDs.first != surface.id)
        #expect(restored.focusedSurfaceID == restored.paneIDs.first)
        guard case let .surface(restoredSurface) = restored.root else {
            Issue.record("expected a surface node")
            return
        }
        #expect(restoredSurface.id == restored.focusedSurfaceID)
        #expect(restoredSurface.terminalHistory == "hello")
        #expect(restoredSurface.agentResume?.sessionID == "session-1")
    }

    @Test("restarts the uptime clock when a closed tab is reopened")
    @MainActor
    func regeneratingIDsResetsCreatedAt() {
        let tab = TabSession(
            id: makeTabID(1),
            initialSurface: makeSurface(id: 1, path: "/repo"),
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )

        let before = Date()
        let restored = tab.regeneratingIDs()

        #expect(restored.createdAt >= before)
    }

    @Test("regenerates every pane ID in a split tab and remaps focus and layout")
    @MainActor
    func regeneratingIDsSplitTab() throws {
        let first = makeSurface(id: 1, path: "/first")
        let second = makeSurface(id: 2, path: "/second")
        var tab = TabSession(id: makeTabID(1), initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        try tab.updateSplitRatio(0.3, at: [])
        try tab.focus(surface: first.id)

        let restored = tab.regeneratingIDs()

        #expect(restored.paneIDs.count == 2)
        #expect(Set(restored.paneIDs).isDisjoint(with: [first.id, second.id]))
        #expect(restored.paneIDs.count == Set(restored.paneIDs).count)
        guard case let .split(orientation, ratio, newFirst, newSecond) = restored.root
        else {
            Issue.record("expected a split node")
            return
        }
        #expect(orientation == .horizontal)
        #expect(abs(ratio - 0.3) < 0.0001)
        #expect(restored.focusedSurfaceID == newFirst.paneIDs.first)
        #expect(restored.focusedSurfaceID != first.id)
        #expect(newSecond.paneIDs.first != second.id)
    }

    @Test("regenerates browser pane IDs in a mixed tab")
    @MainActor
    func regeneratingIDsMixedTab() throws {
        let terminal = makeSurface(id: 1, path: "/repo")
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(2)),
            url: URL(string: "https://example.com")!
        )
        var tab = TabSession(id: makeTabID(1), initialSurface: terminal)
        try tab.split(browser: browser, direction: .right)

        let restored = tab.regeneratingIDs()

        #expect(restored.surfaceIDs.count == 1)
        #expect(restored.surfaceIDs.first != terminal.id)
        let restoredBrowserID = restored.paneIDs.first { $0 != restored.surfaceIDs.first }
        #expect(restoredBrowserID != nil)
        #expect(restoredBrowserID != browser.id)
        #expect(restored.root.browserState(with: restoredBrowserID!)?.url == browser.url)
        #expect(restored.focusedSurfaceID == restoredBrowserID)
    }

    private func makeTabID(_ value: UInt8) -> TabID {
        TabID(rawValue: makeUUID(value))
    }

    private func makeSurface(
        id: UInt8,
        path: String
    ) -> TerminalSurfaceState {
        TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(id)),
            workingDirectory: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}
