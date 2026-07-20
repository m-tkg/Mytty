import AppKit
import GhosttyAdapter
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Terminal appearance integration")
struct TerminalAppearanceIntegrationTests {
    @Test("maps explicit and system appearances to AppKit and libghostty")
    @MainActor
    func appearanceMapping() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))

        #expect(TerminalAppearance.system.appKitAppearance == nil)
        #expect(TerminalAppearance.light.appKitAppearance?.name == .aqua)
        #expect(TerminalAppearance.dark.appKitAppearance?.name == .darkAqua)
        #expect(
            TerminalAppearance.system.ghosttyColorScheme(
                effectiveAppearance: light
            ) == .light
        )
        #expect(
            TerminalAppearance.system.ghosttyColorScheme(
                effectiveAppearance: dark
            ) == .dark
        )
        #expect(
            TerminalAppearance.light.ghosttyColorScheme(
                effectiveAppearance: dark
            ) == .light
        )
        #expect(
            TerminalAppearance.dark.ghosttyColorScheme(
                effectiveAppearance: light
            ) == .dark
        )
    }

    @Test("terminal windows are transparent-capable before their first surface")
    @MainActor
    func transparentWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .white

        TerminalWindowController.prepareWindowForLiveTransparency(window)

        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
    }

    @Test("renders a readable centered title over a transparent terminal")
    @MainActor
    func customTitlebar() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let titlebar = TerminalTitlebarView()

        TerminalWindowController.installTitlebar(titlebar, in: window)
        titlebar.update(
            title: "Codex - project",
            resourceURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        )
        titlebar.layoutSubtreeIfNeeded()

        let frameView = try #require(window.contentView?.superview)
        #expect(window.titleVisibility == .hidden)
        #expect(titlebar.superview === frameView)
        #expect(titlebar.contentOverlay.superview === frameView)
        #expect(titlebar.material == .titlebar)
        #expect(titlebar.blendingMode == .behindWindow)
        #expect(titlebar.state == .followsWindowActiveState)
        #expect(titlebar.displayedTitle == "Codex - project")
        #expect(titlebar.titleColor == .labelColor)
        #expect(abs(titlebar.titleGroupMidX - titlebar.bounds.midX) < 0.5)
        #expect(titlebar.frame.minY >= window.contentView?.frame.maxY ?? 0)
    }
}
