import Foundation
import Testing

@testable import MyTTYCore

@Suite("Window session")
struct WindowSessionTests {
    @Test("adds and selects tabs")
    func addAndSelectTabs() throws {
        let first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let second = makeTab(id: 2, surfaceID: 12, path: "/second")
        var window = makeWindow(tab: first)

        try window.add(tab: second, select: false)
        #expect(window.tabs == [first, second])
        #expect(window.selectedTabID == first.id)

        try window.select(tab: second.id)
        #expect(window.selectedTabID == second.id)
        #expect(window.selectedTab == second)
    }

    @Test("moves and renames tabs without changing selection")
    func moveAndRenameTabs() throws {
        let first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let second = makeTab(id: 2, surfaceID: 12, path: "/second")
        let third = makeTab(id: 3, surfaceID: 13, path: "/third")
        var window = makeWindow(tab: first)
        try window.add(tab: second, select: true)
        try window.add(tab: third, select: false)

        try window.move(tab: third.id, to: 0)
        #expect(window.tabs.map(\.id) == [third.id, first.id, second.id])
        #expect(window.selectedTabID == second.id)

        try window.move(tab: third.id, to: 2)
        #expect(window.tabs.map(\.id) == [first.id, second.id, third.id])

        try window.rename(tab: second.id, title: "  Build logs  ")
        #expect(window.tabs[1].pinnedTitle == "Build logs")
        try window.rename(tab: second.id, title: "   ")
        #expect(window.tabs[1].pinnedTitle == nil)

        #expect(throws: WindowSessionError.invalidTabIndex(3)) {
            try window.move(tab: first.id, to: 3)
        }
        let missingTab = TabID()
        #expect(throws: WindowSessionError.tabNotFound(missingTab)) {
            try window.rename(tab: missingTab, title: "Missing")
        }
    }

    @Test("selects the neighboring tab after close")
    func closeSelectedTab() throws {
        let first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let second = makeTab(id: 2, surfaceID: 12, path: "/second")
        let third = makeTab(id: 3, surfaceID: 13, path: "/third")
        var window = makeWindow(tab: first)
        try window.add(tab: second, select: true)
        try window.add(tab: third, select: false)

        try window.close(tab: second.id)

        #expect(window.tabs == [first, third])
        #expect(window.selectedTabID == third.id)

        try window.close(tab: third.id)
        #expect(window.tabs == [first])
        #expect(window.selectedTabID == first.id)
    }

    @Test("detaches a tab for transfer and reselects a neighbor")
    func detachTab() throws {
        let first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let second = makeTab(id: 2, surfaceID: 12, path: "/second")
        let third = makeTab(id: 3, surfaceID: 13, path: "/third")
        var window = makeWindow(tab: first)
        try window.add(tab: second, select: true)
        try window.add(tab: third, select: false)

        let detached = try window.detach(tab: second.id)

        #expect(detached == second)
        #expect(window.tabs == [first, third])
        #expect(window.selectedTabID == third.id)

        try window.detach(tab: first.id)
        #expect(window.tabs == [third])
        #expect(window.selectedTabID == third.id)

        let missingTab = TabID()
        #expect(throws: WindowSessionError.tabNotFound(missingTab)) {
            try window.detach(tab: missingTab)
        }
    }

    @Test("detaches the last tab leaving the window empty")
    func detachLastTab() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/first")
        var window = makeWindow(tab: tab)

        let detached = try window.detach(tab: tab.id)

        #expect(detached == tab)
        #expect(window.tabs.isEmpty)
    }

    @Test("inserts a tab at a requested position")
    func insertTab() throws {
        let first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let second = makeTab(id: 2, surfaceID: 12, path: "/second")
        let third = makeTab(id: 3, surfaceID: 13, path: "/third")
        var window = makeWindow(tab: first)
        try window.add(tab: second, select: false)

        try window.insert(tab: third, at: 1, select: true)
        #expect(window.tabs.map(\.id) == [first.id, third.id, second.id])
        #expect(window.selectedTabID == third.id)

        let fourth = makeTab(id: 4, surfaceID: 14, path: "/fourth")
        try window.insert(tab: fourth, at: 3, select: false)
        #expect(window.tabs.map(\.id)
            == [first.id, third.id, second.id, fourth.id])
        #expect(window.selectedTabID == third.id)

        #expect(throws: WindowSessionError.duplicateTab(first.id)) {
            try window.insert(tab: first, at: 0, select: false)
        }
        let fifth = makeTab(id: 5, surfaceID: 15, path: "/fifth")
        #expect(throws: WindowSessionError.invalidTabIndex(5)) {
            try window.insert(tab: fifth, at: 5, select: false)
        }
    }

    @Test("updates a terminal working directory")
    func updateWorkingDirectory() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/old")
        var window = makeWindow(tab: tab)
        let updated = URL(fileURLWithPath: "/new", isDirectory: true)

        try window.updateWorkingDirectory(
            updated,
            for: tab.focusedSurfaceID
        )

        #expect(
            window.selectedTab?.root
                == .surface(
                    TerminalSurfaceState(
                        id: tab.focusedSurfaceID,
                        workingDirectory: updated
                    )
                )
        )
    }

    @Test("focuses a surface and selects its tab")
    func focusSurface() throws {
        var first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let nestedSurface = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(12)),
            workingDirectory: URL(fileURLWithPath: "/nested", isDirectory: true)
        )
        try first.split(
            surface: first.focusedSurfaceID,
            adding: nestedSurface,
            direction: .right
        )
        let second = makeTab(id: 2, surfaceID: 13, path: "/second")
        var window = makeWindow(tab: first)
        try window.add(tab: second, select: true)

        try window.focus(surface: nestedSurface.id)

        #expect(window.selectedTabID == first.id)
        #expect(window.selectedTab?.focusedSurfaceID == nestedSurface.id)
    }

    @Test("routes split mutations through the selected tab")
    func splitMutations() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/first")
        let added = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(12)),
            workingDirectory: URL(fileURLWithPath: "/second", isDirectory: true)
        )
        var window = makeWindow(tab: tab)

        try window.splitFocusedSurface(adding: added, direction: .right)
        #expect(window.selectedTab?.focusedSurfaceID == added.id)
        #expect(window.selectedTab?.surfaceIDs == [tab.focusedSurfaceID, added.id])

        let moved = window.focusPane(in: .left)
        #expect(moved)
        #expect(window.selectedTab?.focusedSurfaceID == tab.focusedSurfaceID)

        try window.updateSelectedSplitRatio(0.65, at: [])
        guard case let .split(_, ratio, _, _) = window.selectedTab?.root else {
            Issue.record("Expected selected tab split")
            return
        }
        #expect(ratio == 0.65)

        try window.closeSurface(tab.focusedSurfaceID)
        #expect(window.selectedTab?.root == .surface(added))
        #expect(window.selectedTab?.focusedSurfaceID == added.id)
    }

    @Test("routes outer splits through the selected tab")
    func outerSplitMutations() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/first")
        let added = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(12)),
            workingDirectory: URL(fileURLWithPath: "/second", isDirectory: true)
        )
        let outer = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(13)),
            workingDirectory: URL(fileURLWithPath: "/outer", isDirectory: true)
        )
        var window = makeWindow(tab: tab)
        try window.splitFocusedSurface(adding: added, direction: .down)

        try window.splitOuterFocusedSurface(adding: outer, direction: .right)

        #expect(window.selectedTab?.focusedSurfaceID == outer.id)
        guard case let .split(orientation, _, first, second) =
            window.selectedTab?.root
        else {
            Issue.record("Expected selected tab split")
            return
        }
        #expect(orientation == .horizontal)
        #expect(first.surfaceIDs == [tab.focusedSurfaceID, added.id])
        #expect(second == .surface(outer))
    }

    @Test("splits a surface in an unselected tab without selecting or focusing it")
    func backgroundSplit() throws {
        let background = makeTab(id: 1, surfaceID: 11, path: "/background")
        let selected = makeTab(id: 2, surfaceID: 12, path: "/selected")
        var window = makeWindow(tab: background)
        try window.add(tab: selected, select: true)
        let added = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(13)),
            workingDirectory: URL(fileURLWithPath: "/added", isDirectory: true)
        )

        try window.split(
            surface: background.focusedSurfaceID,
            adding: added,
            direction: .right
        )

        #expect(window.selectedTabID == selected.id)
        let backgroundTab = window.tabs.first { $0.id == background.id }
        #expect(
            backgroundTab?.surfaceIDs
                == [background.focusedSurfaceID, added.id]
        )
        #expect(
            backgroundTab?.focusedSurfaceID == background.focusedSurfaceID
        )

        let unknownSurface = TerminalSurfaceID(rawValue: makeUUID(19))
        #expect(throws: WindowSessionError.surfaceNotFound(unknownSurface)) {
            try window.split(
                surface: unknownSurface,
                adding: TerminalSurfaceState(
                    id: TerminalSurfaceID(rawValue: makeUUID(14)),
                    workingDirectory: URL(
                        fileURLWithPath: "/other",
                        isDirectory: true
                    )
                ),
                direction: .right
            )
        }
    }

    @Test("splits next to a browser pane in the background")
    func backgroundSplitBrowserAnchor() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/first")
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(12)),
            url: URL(string: "https://example.com/")!
        )
        var window = makeWindow(tab: tab)
        try window.splitFocusedBrowser(adding: browser, direction: .right)
        try window.focus(pane: tab.focusedSurfaceID)
        let added = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(13)),
            workingDirectory: URL(fileURLWithPath: "/added", isDirectory: true)
        )

        try window.split(surface: browser.id, adding: added, direction: .down)

        let updated = window.selectedTab
        #expect(
            updated?.paneIDs == [tab.focusedSurfaceID, browser.id, added.id]
        )
        #expect(updated?.focusedSurfaceID == tab.focusedSurfaceID)
    }

    @Test("equalizes panes in a requested tab without selecting it")
    func equalizeRequestedTab() throws {
        var first = makeTab(id: 1, surfaceID: 11, path: "/first")
        let secondPane = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(12)),
            workingDirectory: URL(fileURLWithPath: "/second", isDirectory: true)
        )
        let thirdPane = TerminalSurfaceState(
            id: TerminalSurfaceID(rawValue: makeUUID(13)),
            workingDirectory: URL(fileURLWithPath: "/third", isDirectory: true)
        )
        try first.split(
            surface: first.focusedSurfaceID,
            adding: secondPane,
            direction: .right
        )
        try first.split(
            surface: secondPane.id,
            adding: thirdPane,
            direction: .right
        )
        try first.updateSplitRatio(0.8, at: [])
        let second = makeTab(id: 2, surfaceID: 21, path: "/selected")
        var window = makeWindow(tab: first)
        try window.add(tab: second, select: true)

        try window.equalizePanes(in: first.id)

        #expect(window.selectedTabID == second.id)
        guard let equalized = window.tabs.first(where: { $0.id == first.id }),
              case let .split(_, ratio, _, _) = equalized.root
        else {
            Issue.record("Expected equalized background tab")
            return
        }
        #expect(abs(ratio - 1.0 / 3.0) < 0.0001)
    }

    @Test("routes browser pane mutations through the selected tab")
    func browserPaneMutations() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/first")
        let browser = BrowserPaneState(
            id: TerminalSurfaceID(rawValue: makeUUID(12)),
            url: URL(string: "https://example.com/start")!
        )
        var window = makeWindow(tab: tab)

        try window.splitFocusedBrowser(adding: browser, direction: .right)
        #expect(window.selectedTab?.paneIDs == [tab.focusedSurfaceID, browser.id])
        #expect(window.selectedTab?.focusedSurfaceID == browser.id)

        let updatedURL = URL(string: "https://example.com/next")!
        try window.updateBrowserURL(updatedURL, for: browser.id)
        #expect(window.selectedTab?.root.browserState(with: browser.id)?.url == updatedURL)

        try window.focus(pane: tab.focusedSurfaceID)
        #expect(window.selectedTab?.focusedSurfaceID == tab.focusedSurfaceID)

        try window.closePane(browser.id)
        #expect(window.selectedTab?.root == tab.root)
    }

    @Test("rejects invalid tab mutations atomically")
    func invalidMutations() throws {
        let tab = makeTab(id: 1, surfaceID: 11, path: "/first")
        let unknownTab = TabID(rawValue: makeUUID(9))
        let unknownSurface = TerminalSurfaceID(rawValue: makeUUID(19))
        var window = makeWindow(tab: tab)
        let original = window

        #expect(throws: WindowSessionError.duplicateTab(tab.id)) {
            try window.add(tab: tab, select: true)
        }
        #expect(throws: WindowSessionError.tabNotFound(unknownTab)) {
            try window.select(tab: unknownTab)
        }
        #expect(throws: WindowSessionError.tabNotFound(unknownTab)) {
            try window.close(tab: unknownTab)
        }
        #expect(throws: WindowSessionError.cannotCloseLastTab) {
            try window.close(tab: tab.id)
        }
        #expect(throws: WindowSessionError.surfaceNotFound(unknownSurface)) {
            try window.updateWorkingDirectory(
                URL(fileURLWithPath: "/new", isDirectory: true),
                for: unknownSurface
            )
        }
        #expect(throws: WindowSessionError.surfaceNotFound(unknownSurface)) {
            try window.focus(surface: unknownSurface)
        }
        #expect(window == original)
    }

    private func makeWindow(tab: TabSession) -> WindowSession {
        WindowSession(
            id: WindowID(rawValue: makeUUID(20)),
            frame: WindowFrame(x: 100, y: 100, width: 1100, height: 720),
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func makeTab(
        id: UInt8,
        surfaceID: UInt8,
        path: String
    ) -> TabSession {
        TabSession(
            id: TabID(rawValue: makeUUID(id)),
            initialSurface: TerminalSurfaceState(
                id: TerminalSurfaceID(rawValue: makeUUID(surfaceID)),
                workingDirectory: URL(
                    fileURLWithPath: path,
                    isDirectory: true
                )
            )
        )
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}
