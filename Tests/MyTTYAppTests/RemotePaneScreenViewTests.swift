import AppKit
import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

/// The host only pushes a new snapshot when a mirrored pane's visible text
/// or cursor actually changes (`RemotePaneWatchTracker`), so a viewport
/// resize with no new content has no `update(lines:...)` call to ride along
/// with. These tests cover the view's own path for picking that resize up:
/// observing the clip view's frame directly.
@Suite("Remote pane screen view")
struct RemotePaneScreenViewTests {
    @MainActor
    private static func makeScreenView() -> (NSScrollView, RemotePaneScreenView) {
        let screenView = RemotePaneScreenView(
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = screenView
        return (scrollView, screenView)
    }

    /// Builds styled runs the same way `RemotePaneView.update(screen:)`
    /// does, since `RemotePaneRun`'s initializer isn't public outside
    /// `MyTTYRemoteKit`.
    private static func run(text: String) -> [[RemotePaneRun]] {
        RemotePaneScreenRenderer.renderedLines(
            text: text,
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: []
        )
    }

    /// Regression test for the bug: closing a sibling pane widens the
    /// scroll view but, with no new host snapshot, nothing used to tell
    /// `documentView` to widen along with it.
    @Test("widens the document view when the viewport grows with no new content")
    @MainActor
    func widensWithViewportGrowth() {
        let (scrollView, screenView) = Self.makeScreenView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        scrollView.layoutSubtreeIfNeeded()
        #expect(screenView.frame.width <= 200)

        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        scrollView.layoutSubtreeIfNeeded()

        #expect(screenView.frame.width >= 599)
    }

    /// `max(width, viewport.width)` in `invalidateContentSize()` means
    /// content wider than the viewport keeps its own width — shrinking the
    /// viewport must not clip it.
    @Test("keeps the content width when the viewport shrinks below it")
    @MainActor
    func keepsContentWidthWhenViewportShrinks() {
        let (scrollView, screenView) = Self.makeScreenView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 100)
        scrollView.layoutSubtreeIfNeeded()

        let longLine = String(repeating: "x", count: 200)
        screenView.update(
            lines: Self.run(text: longLine),
            plainText: longLine,
            isAltScreen: false
        )
        let wideWidth = screenView.frame.width
        #expect(wideWidth > 800)

        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        scrollView.layoutSubtreeIfNeeded()

        #expect(abs(screenView.frame.width - wideWidth) < 1)
    }

    /// `invalidateContentSize()` guards against re-triggering itself once
    /// the frame has settled; repeated notifications for a viewport that
    /// isn't actually changing size must not misbehave.
    @Test("tolerates repeated notifications for an unchanged viewport size")
    @MainActor
    func repeatedSameSizeNotificationsAreStable() {
        let (scrollView, screenView) = Self.makeScreenView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        scrollView.layoutSubtreeIfNeeded()
        let width = screenView.frame.width

        for _ in 0..<5 {
            NotificationCenter.default.post(
                name: NSView.frameDidChangeNotification,
                object: scrollView.contentView
            )
        }

        #expect(screenView.frame.width == width)
    }
}
