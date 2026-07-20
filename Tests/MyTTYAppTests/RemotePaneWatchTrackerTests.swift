import Foundation
import Testing

@testable import MyTTYApp

@Suite("Remote pane watch tracker")
struct RemotePaneWatchTrackerTests {
    private let content = RemotePaneContent(
        text: "hello",
        cursorRow: 2,
        cursorColumn: 5
    )

    @Test("an unwatched pane never yields content")
    func unwatchedPaneYieldsNothing() {
        var tracker = RemotePaneWatchTracker()
        #expect(tracker.contentToSend(paneID: "pane-1", current: content) == nil)
    }

    @Test("a freshly watched pane yields its current content once")
    func watchedPaneYieldsFirstContent() {
        var tracker = RemotePaneWatchTracker()
        tracker.watch(paneID: "pane-1")
        #expect(
            tracker.contentToSend(paneID: "pane-1", current: content) == content
        )
    }

    @Test("unchanged content is not resent")
    func unchangedContentIsNotResent() {
        var tracker = RemotePaneWatchTracker()
        tracker.watch(paneID: "pane-1")
        _ = tracker.contentToSend(paneID: "pane-1", current: content)
        #expect(tracker.contentToSend(paneID: "pane-1", current: content) == nil)
    }

    @Test("changed text is resent")
    func changedTextIsResent() {
        var tracker = RemotePaneWatchTracker()
        tracker.watch(paneID: "pane-1")
        _ = tracker.contentToSend(paneID: "pane-1", current: content)
        var updated = content
        updated.text = "world"
        #expect(
            tracker.contentToSend(paneID: "pane-1", current: updated) == updated
        )
    }

    @Test("a cursor move alone is resent even when the text is unchanged")
    func cursorMoveAloneIsResent() {
        var tracker = RemotePaneWatchTracker()
        tracker.watch(paneID: "pane-1")
        _ = tracker.contentToSend(paneID: "pane-1", current: content)
        var moved = content
        moved.cursorColumn = 6
        #expect(
            tracker.contentToSend(paneID: "pane-1", current: moved) == moved
        )
    }

    @Test("unwatching forgets the last sent content so re-watching resends")
    func unwatchingResetsLastSentContent() {
        var tracker = RemotePaneWatchTracker()
        tracker.watch(paneID: "pane-1")
        _ = tracker.contentToSend(paneID: "pane-1", current: content)
        tracker.unwatch(paneID: "pane-1")
        tracker.watch(paneID: "pane-1")

        #expect(
            tracker.contentToSend(paneID: "pane-1", current: content) == content
        )
    }

    @Test("tracks multiple panes independently")
    func tracksMultiplePanesIndependently() {
        var tracker = RemotePaneWatchTracker()
        tracker.watch(paneID: "pane-1")
        tracker.watch(paneID: "pane-2")
        let first = RemotePaneContent(text: "a", cursorRow: 0, cursorColumn: 1)
        let second = RemotePaneContent(text: "b", cursorRow: 0, cursorColumn: 1)

        #expect(tracker.contentToSend(paneID: "pane-1", current: first) == first)
        #expect(tracker.contentToSend(paneID: "pane-2", current: second) == second)
        #expect(tracker.contentToSend(paneID: "pane-1", current: first) == nil)
        var updated = second
        updated.text = "c"
        #expect(
            tracker.contentToSend(paneID: "pane-2", current: updated) == updated
        )
    }
}
