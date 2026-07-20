import Foundation

/// Decides whether a remote pane view should keep auto-following the bottom
/// of its scrollback, so screen updates never yank the view down while the
/// user has scrolled up to read.
///
/// Feed it the content frame (top offset in the scroll view's coordinate
/// space plus content height) and the viewport height on every layout
/// change. It distinguishes user scrolling from content/viewport changes by
/// what moved: an offset change at constant sizes is the user scrolling and
/// re-decides the pin; a size change keeps the current pin and, while
/// pinned, asks the caller to scroll back to the bottom.
public struct RemoteScrollPinTracker: Sendable {
    public private(set) var isPinnedToBottom = true
    private var lastContentHeight: Double?
    private var lastViewportHeight: Double?

    /// Slack under which the content bottom still counts as on-screen, so
    /// sub-line wiggle from padding or bounce doesn't unpin.
    private let threshold: Double

    public init(threshold: Double = 24) {
        self.threshold = threshold
    }

    /// Consumes one layout observation. Returns true when the caller should
    /// scroll the content bottom back into view now.
    public mutating func update(
        contentTopOffset: Double,
        contentHeight: Double,
        viewportHeight: Double
    ) -> Bool {
        let distanceBelowViewport =
            contentTopOffset + contentHeight - viewportHeight
        let atBottom = distanceBelowViewport <= threshold

        let sizesUnchanged =
            (lastContentHeight.map { abs(contentHeight - $0) < 0.5 } ?? false)
            && (lastViewportHeight.map { abs(viewportHeight - $0) < 0.5 } ?? false)
        lastContentHeight = contentHeight
        lastViewportHeight = viewportHeight

        if sizesUnchanged {
            isPinnedToBottom = atBottom
            return false
        }
        return isPinnedToBottom && !atBottom
    }
}
