import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemoteScrollPinTrackerTests {
    @Test
    func initialTallContentRequestsScrollToBottom() {
        var tracker = RemoteScrollPinTracker()
        let shouldFollow = tracker.update(
            contentTopOffset: 0, contentHeight: 2000, viewportHeight: 600
        )
        #expect(shouldFollow)
        #expect(tracker.isPinnedToBottom)
    }

    @Test
    func contentShorterThanViewportNeedsNoScroll() {
        var tracker = RemoteScrollPinTracker()
        let shouldFollow = tracker.update(
            contentTopOffset: 0, contentHeight: 300, viewportHeight: 600
        )
        #expect(!shouldFollow)
        #expect(tracker.isPinnedToBottom)
    }

    @Test
    func contentGrowthWhilePinnedRequestsScroll() {
        var tracker = RemoteScrollPinTracker()
        _ = tracker.update(
            contentTopOffset: 0, contentHeight: 2000, viewportHeight: 600
        )
        // The requested scroll landed at the bottom.
        _ = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        // New lines arrive: same offset, taller content.
        let shouldFollow = tracker.update(
            contentTopOffset: -1400, contentHeight: 2100, viewportHeight: 600
        )
        #expect(shouldFollow)
        #expect(tracker.isPinnedToBottom)
    }

    @Test
    func scrollingUpUnpinsAndStopsFollowing() {
        var tracker = RemoteScrollPinTracker()
        _ = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        // Pure scroll (sizes unchanged): the user dragged up to read.
        let duringDrag = tracker.update(
            contentTopOffset: -800, contentHeight: 2000, viewportHeight: 600
        )
        #expect(!duringDrag)
        #expect(!tracker.isPinnedToBottom)
        // A screen update while unpinned must not yank the view down.
        let onUpdate = tracker.update(
            contentTopOffset: -800, contentHeight: 2100, viewportHeight: 600
        )
        #expect(!onUpdate)
        #expect(!tracker.isPinnedToBottom)
    }

    @Test
    func returningToBottomRepinsAndResumesFollowing() {
        var tracker = RemoteScrollPinTracker()
        _ = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        _ = tracker.update(
            contentTopOffset: -800, contentHeight: 2000, viewportHeight: 600
        )
        #expect(!tracker.isPinnedToBottom)
        // The user scrolls back down to the bottom.
        _ = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        #expect(tracker.isPinnedToBottom)
        let shouldFollow = tracker.update(
            contentTopOffset: -1400, contentHeight: 2100, viewportHeight: 600
        )
        #expect(shouldFollow)
    }

    @Test
    func viewportShrinkWhilePinnedRequestsScrollAndKeepsPin() {
        var tracker = RemoteScrollPinTracker()
        _ = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        // The software keyboard appears, shrinking the viewport.
        let shouldFollow = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 340
        )
        #expect(shouldFollow)
        #expect(tracker.isPinnedToBottom)
    }

    @Test
    func subThresholdWiggleAtBottomStaysPinned() {
        var tracker = RemoteScrollPinTracker()
        _ = tracker.update(
            contentTopOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        // Bounce/padding jitter within the threshold: still at bottom.
        _ = tracker.update(
            contentTopOffset: -1390, contentHeight: 2000, viewportHeight: 600
        )
        #expect(tracker.isPinnedToBottom)
    }
}
