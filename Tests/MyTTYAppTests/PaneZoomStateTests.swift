import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Pane zoom state")
struct PaneZoomStateTests {
    @Test("toggles the focused pane only when a tab has multiple panes")
    func togglesFocusedPane() throws {
        let first = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let second = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        var tab = TabSession(initialSurface: first)
        var state = PaneZoomState()

        let singlePaneResult = state.toggle(for: tab)
        #expect(!singlePaneResult)
        try tab.split(surface: first.id, adding: second, direction: .right)

        let zoomedResult = state.toggle(for: tab)
        #expect(zoomedResult)
        #expect(state.target(for: tab) == second.id)
        let restoredResult = state.toggle(for: tab)
        #expect(!restoredResult)
        #expect(state.target(for: tab) == nil)
    }

    @Test("follows focus and removes zoom when only one pane remains")
    func followsTabChanges() throws {
        let first = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let second = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let third = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        var tab = TabSession(initialSurface: first)
        try tab.split(surface: first.id, adding: second, direction: .right)
        try tab.split(surface: second.id, adding: third, direction: .down)
        var state = PaneZoomState()

        let zoomedResult = state.toggle(for: tab)
        #expect(zoomedResult)
        try tab.focus(surface: first.id)
        state.synchronize(with: tab)
        #expect(state.target(for: tab) == first.id)

        try tab.close(pane: first.id)
        state.synchronize(with: tab)
        #expect(state.target(for: tab) == tab.focusedSurfaceID)

        try tab.close(pane: tab.focusedSurfaceID)
        state.synchronize(with: tab)
        #expect(state.target(for: tab) == nil)
    }
}
