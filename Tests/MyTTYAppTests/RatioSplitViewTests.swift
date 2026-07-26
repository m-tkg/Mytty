import AppKit
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Ratio split view")
struct RatioSplitViewTests {
    @Test("keeps a new nested split at half after receiving its final size")
    @MainActor
    func nestedSplitUsesFinalSize() {
        let split = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        split.addArrangedSubview(NSView())
        split.addArrangedSubview(NSView())

        split.frame = NSRect(x: 0, y: 0, width: 180, height: 320)
        split.layoutSubtreeIfNeeded()
        split.frame.size.width = 620
        split.layoutSubtreeIfNeeded()

        let available = split.bounds.width - split.dividerThickness
        #expect(
            abs(split.subviews[0].frame.width - available * 0.5) <= 2
        )
    }

    /// A remote pane brings its own Auto Layout chrome (header labels,
    /// banner, scroll view); the split must still honor the stored ratio
    /// instead of letting those constraints squeeze the pane.
    @Test("splits a terminal and a remote pane at the stored ratio")
    @MainActor
    func remotePaneSplitHonorsStoredRatio() {
        let split = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in }
        )
        let remote = RemotePaneView(
            paneID: TerminalSurfaceID(),
            hostID: "host-1",
            remotePaneID: "pane-1",
            hostName: "Other Mac",
            title: "zsh",
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        split.addArrangedSubview(PaneHostView(content: NSView()))
        split.addArrangedSubview(PaneHostView(content: remote))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = split
        split.layoutSubtreeIfNeeded()
        split.applyCurrentRatio()
        split.layoutSubtreeIfNeeded()

        let available = split.bounds.width - split.dividerThickness
        #expect(
            abs(split.subviews[0].frame.width - available * 0.5) <= 2
        )
        #expect(
            abs(split.subviews[1].frame.width - available * 0.5) <= 2
        )
    }

    @Test("preserves a user-adjusted split ratio when the container resizes")
    @MainActor
    func resizedSplitPreservesCurrentRatio() {
        var userResizeCount = 0
        let split = RatioSplitView(
            orientation: .horizontal,
            ratio: 0.5,
            onRatioChanged: { _ in },
            onUserResize: { userResizeCount += 1 }
        )
        split.addArrangedSubview(NSView())
        split.addArrangedSubview(NSView())
        split.frame = NSRect(x: 0, y: 0, width: 400, height: 320)
        split.layoutSubtreeIfNeeded()

        let available = split.bounds.width - split.dividerThickness
        split.setPosition(available * 0.7, ofDividerAt: 0)
        split.splitViewDidResizeSubviews(
            Notification(
                name: NSSplitView.didResizeSubviewsNotification,
                object: split,
                userInfo: [
                    "NSSplitViewDividerIndex": 0,
                    "NSSplitViewUserResizeKey": 1,
                ]
            )
        )
        split.frame.size.width = 700
        split.layoutSubtreeIfNeeded()

        #expect(abs(split.firstPaneRatio - 0.7) < 0.001)
        #expect(userResizeCount == 1)
    }
}
