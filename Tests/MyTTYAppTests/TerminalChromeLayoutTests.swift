import AppKit
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Terminal chrome layout")
struct TerminalChromeLayoutTests {
    @Test("keeps left tabs from taking over the native title bar")
    @MainActor
    func leftTabsDoNotBecomeAWindowSidebar() {
        let item = TerminalWindowController.makeTabPanelSplitItem(
            viewController: NSViewController()
        )

        #expect(item.behavior == .default)
    }

    @Test("prefixes a terminal title with the active agent name")
    func agentWindowTitle() {
        #expect(
            TerminalWindowTitle.make(
                baseTitle: "[~/repo]",
                activeProvider: .codex
            ) == "Codex - [~/repo]"
        )
        #expect(
            TerminalWindowTitle.make(
                baseTitle: "project",
                activeProvider: .claudeCode
            ) == "Claude Code - project"
        )
        #expect(
            TerminalWindowTitle.make(
                baseTitle: "project",
                activeProvider: .openCode
            ) == "OpenCode - project"
        )
        #expect(
            TerminalWindowTitle.make(
                baseTitle: "project",
                activeProvider: .antigravity
            ) == "Gemini (Antigravity) - project"
        )
        #expect(
            TerminalWindowTitle.make(
                baseTitle: "project",
                activeProvider: .cursor
            ) == "Cursor - project"
        )
        #expect(
            TerminalWindowTitle.make(
                baseTitle: "[~/repo]",
                activeProvider: nil
            ) == "[~/repo]"
        )
    }

    @Test("derives the default title from the first pane's directory even after focus moves")
    func defaultTitleFollowsFirstPane() throws {
        let first = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/repo", isDirectory: true)
        )
        let second = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/other", isDirectory: true)
        )
        var tab = TabSession(initialSurface: first)
        try tab.split(
            surface: first.id,
            adding: second,
            direction: .right
        )

        #expect(tab.focusedSurfaceID == second.id)
        #expect(
            TerminalTabTitle.defaultTitle(
                for: tab,
                localizer: MyTTYLocalizer(language: .english)
            ) == "repo"
        )
    }

    @Test("resets a reused surface host before attaching new chrome")
    @MainActor
    func reusedSurfaceHost() {
        let host = NSView(frame: NSRect(x: 220, y: 0, width: 600, height: 400))
        host.translatesAutoresizingMaskIntoConstraints = false

        TerminalWindowController.prepareSurfaceHostForChrome(host)

        #expect(host.frame.origin == .zero)
        #expect(host.translatesAutoresizingMaskIntoConstraints)
        #expect(host.autoresizingMask.contains(.width))
        #expect(host.autoresizingMask.contains(.height))
    }

    @Test("top tabs and terminal content fill the window width")
    @MainActor
    func topChromeFillsWidth() {
        let tabs = NSView()
        let content = NSView()
        let root = TerminalWindowController.makeTopChromeRoot(
            tabs: tabs,
            content: content
        )
        root.frame = NSRect(x: 0, y: 0, width: 820, height: 600)

        root.layoutSubtreeIfNeeded()

        #expect(tabs.frame.minX == 0)
        #expect(tabs.frame.width == 820)
        #expect(tabs.frame.height == 44)
        #expect(content.frame.minX == 0)
        #expect(content.frame.width == 820)
        #expect(content.frame.height == 555)
    }

    @Test("bottom tabs and terminal content fill the window width")
    @MainActor
    func bottomChromeFillsWidth() {
        let tabs = NSView()
        let content = NSView()
        let root = TerminalWindowController.makeBottomChromeRoot(
            tabs: tabs,
            content: content
        )
        root.frame = NSRect(x: 0, y: 0, width: 820, height: 600)

        root.layoutSubtreeIfNeeded()

        #expect(tabs.frame == NSRect(x: 0, y: 0, width: 820, height: 44))
        #expect(content.frame == NSRect(x: 0, y: 45, width: 820, height: 555))
    }

    @Test("replacing tab chrome preserves the outer window frame")
    @MainActor
    func chromeReplacementPreservesWindowFrame() {
        let initialFrame = NSRect(x: 90, y: 110, width: 1120, height: 720)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: TerminalWindowGeometry.styleMask,
            backing: .buffered,
            defer: false
        )
        window.setFrame(initialFrame, display: false)
        let controller = NSViewController()
        controller.view = NSView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )

        TerminalWindowGeometry.installContentViewController(
            controller,
            in: window
        )

        #expect(window.frame == initialFrame)
    }

    @Test("reserves the bottom edge for the status bar")
    @MainActor
    func statusBarChrome() {
        let content = NSView()
        let statusBar = NSView()
        let root = TerminalWindowController.makeStatusChromeRoot(
            content: content,
            statusBar: statusBar
        )
        root.frame = NSRect(x: 0, y: 0, width: 820, height: 600)

        root.layoutSubtreeIfNeeded()

        #expect(content.frame == NSRect(x: 0, y: 24, width: 820, height: 576))
        #expect(statusBar.frame == NSRect(x: 0, y: 0, width: 820, height: 24))
    }

    @Test("lays out attached panes before redrawing terminal surfaces")
    @MainActor
    func paneAttachmentRedrawOrder() {
        let host = NSView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400)
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        let split = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        split.addArrangedSubview(NSView())
        split.addArrangedSubview(NSView())
        split.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            split.topAnchor.constraint(equalTo: host.topAnchor),
            split.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        var redrawCount = 0
        var focusRestoreCount = 0
        var scheduledRedraw: (@MainActor () -> Void)?
        var dimensionsAtRefresh: [CGFloat] = []
        TerminalWindowController.finalizePaneAttachment(
            in: host,
            redraw: {
                redrawCount += 1
                dimensionsAtRefresh = [
                    split.bounds.width,
                    split.subviews[0].bounds.width,
                    split.subviews[1].bounds.width,
                ]
            },
            restoreFocus: { focusRestoreCount += 1 },
            schedule: { scheduledRedraw = $0 }
        )

        #expect(dimensionsAtRefresh.allSatisfy { $0 > 0 })
        #expect(abs(split.firstPaneRatio - 0.5) < 0.001)
        #expect(redrawCount == 1)
        #expect(focusRestoreCount == 0)

        scheduledRedraw?()

        #expect(redrawCount == 2)
        #expect(focusRestoreCount == 1)
    }

    @Test("claims a tab before attaching views to block focus reentry")
    @MainActor
    func renderClaimBlocksReentry() {
        let tabID = TabID()
        var renderedTabID: TabID?

        #expect(
            TerminalWindowController.claimRender(
                tabID,
                renderedTabID: &renderedTabID
            )
        )
        #expect(renderedTabID == tabID)
        #expect(
            !TerminalWindowController.claimRender(
                tabID,
                renderedTabID: &renderedTabID
            )
        )
    }

    @Test("ignores surface focus callbacks while attaching split views")
    @MainActor
    func attachmentFocusDoesNotOverrideSession() {
        let selected = TerminalSurfaceID()
        let attaching = TerminalSurfaceID()

        #expect(
            !TerminalWindowController.shouldCommitFocusChange(
                focused: true,
                isAttaching: true,
                selectedSurfaceID: selected,
                eventSurfaceID: attaching
            )
        )
        #expect(
            TerminalWindowController.shouldCommitFocusChange(
                focused: true,
                isAttaching: false,
                selectedSurfaceID: selected,
                eventSurfaceID: attaching
            )
        )
    }

    @Test("applies the ratio when a parent assigns the final split size")
    @MainActor
    func parentSizeAssignmentSplitsAtHalf() {
        let nested = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        nested.addArrangedSubview(NSView())
        nested.addArrangedSubview(NSView())

        let root = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        root.addArrangedSubview(NSView())
        root.addArrangedSubview(nested)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host
        root.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            root.topAnchor.constraint(equalTo: host.topAnchor),
            root.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        TerminalWindowController.finalizePaneAttachment(
            in: host,
            redraw: {},
            schedule: { _ in }
        )

        #expect(abs(nested.firstPaneRatio - 0.5) < 0.001)
    }

    @Test("starts a new surface at half the focused pane size")
    @MainActor
    func initialSplitSurfaceSize() {
        let focusedSize = NSSize(width: 601, height: 401)

        #expect(
            TerminalWindowController.initialSurfaceSize(
                for: .right,
                focusedPaneSize: focusedSize,
                dividerThickness: 1
            ) == NSSize(width: 300, height: 401)
        )
        #expect(
            TerminalWindowController.initialSurfaceSize(
                for: .down,
                focusedPaneSize: focusedSize,
                dividerThickness: 1
            ) == NSSize(width: 601, height: 200)
        )
    }

    @Test("reapplies nested ratios after deferred parent layout")
    @MainActor
    func deferredNestedRatio() {
        let nested = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        nested.addArrangedSubview(NSView())
        nested.addArrangedSubview(NSView())

        let root = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        root.addArrangedSubview(NSView())
        root.addArrangedSubview(nested)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host
        root.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            root.topAnchor.constraint(equalTo: host.topAnchor),
            root.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        var scheduledLayout: (@MainActor () -> Void)?
        TerminalWindowController.finalizePaneAttachment(
            in: host,
            redraw: {},
            schedule: { scheduledLayout = $0 }
        )
        nested.setPosition(0, ofDividerAt: 0)

        #expect(nested.firstPaneRatio < 0.01)

        scheduledLayout?()

        #expect(abs(nested.firstPaneRatio - 0.5) < 0.001)
    }

    @Test("lays out five panes nested to the right without recursion")
    @MainActor
    func fiveRightPanesLayout() {
        var root: NSView = NSView()
        var splits: [RatioSplitView] = []
        for _ in 0..<4 {
            let split = RatioSplitView(
                orientation: .horizontal,
                ratio: 0.5,
                onRatioChanged: { _ in }
            )
            split.addArrangedSubview(NSView())
            split.addArrangedSubview(root)
            root = split
            splits.append(split)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host
        root.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            root.topAnchor.constraint(equalTo: host.topAnchor),
            root.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        TerminalWindowController.finalizePaneAttachment(
            in: host,
            redraw: {},
            schedule: { _ in }
        )

        for (index, split) in splits.enumerated() {
            let available = split.bounds.width - split.dividerThickness
            #expect(
                abs(split.subviews[0].frame.width - available * 0.5) <= 0.5,
                "Split at nesting level \(index) was not half-sized"
            )
        }
    }
}
