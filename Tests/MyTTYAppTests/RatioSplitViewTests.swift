import AppKit
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
