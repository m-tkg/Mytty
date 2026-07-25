import AppKit
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Floating pane placement")
struct FloatingPanePlacementTests {
    /// A visible frame with a non-zero origin, matching a secondary display
    /// sitting to the right of the main one -- makes sure the math uses
    /// `visibleFrame`'s own origin rather than assuming (0, 0).
    private static let visibleFrame = NSRect(
        x: 1920, y: 40, width: 1600, height: 960
    )

    @Test("top edge: docks flush to the top, half height, full width")
    func topEdge() {
        let frames = FloatingPanePlacement.frames(
            edge: .top,
            visibleFrame: Self.visibleFrame,
            extentRatio: 0.5
        )

        #expect(frames.onscreen.size == frames.offscreen.size)
        #expect(frames.onscreen.width == Self.visibleFrame.width)
        #expect(frames.onscreen.height == Self.visibleFrame.height * 0.5)
        #expect(frames.onscreen.minX == Self.visibleFrame.minX)
        #expect(frames.onscreen.maxY == Self.visibleFrame.maxY)

        // Off-screen sits just past the top edge, entirely outside the
        // visible frame.
        #expect(frames.offscreen.minY == Self.visibleFrame.maxY)
        #expect(!Self.visibleFrame.intersects(frames.offscreen))
    }

    @Test("bottom edge: docks flush to the bottom, half height, full width")
    func bottomEdge() {
        let frames = FloatingPanePlacement.frames(
            edge: .bottom,
            visibleFrame: Self.visibleFrame,
            extentRatio: 0.5
        )

        #expect(frames.onscreen.size == frames.offscreen.size)
        #expect(frames.onscreen.width == Self.visibleFrame.width)
        #expect(frames.onscreen.height == Self.visibleFrame.height * 0.5)
        #expect(frames.onscreen.minX == Self.visibleFrame.minX)
        #expect(frames.onscreen.minY == Self.visibleFrame.minY)

        #expect(frames.offscreen.maxY == Self.visibleFrame.minY)
        #expect(!Self.visibleFrame.intersects(frames.offscreen))
    }

    @Test("left edge: docks flush to the left, half width, full height")
    func leftEdge() {
        let frames = FloatingPanePlacement.frames(
            edge: .left,
            visibleFrame: Self.visibleFrame,
            extentRatio: 0.5
        )

        #expect(frames.onscreen.size == frames.offscreen.size)
        #expect(frames.onscreen.height == Self.visibleFrame.height)
        #expect(frames.onscreen.width == Self.visibleFrame.width * 0.5)
        #expect(frames.onscreen.minY == Self.visibleFrame.minY)
        #expect(frames.onscreen.minX == Self.visibleFrame.minX)

        #expect(frames.offscreen.maxX == Self.visibleFrame.minX)
        #expect(!Self.visibleFrame.intersects(frames.offscreen))
    }

    @Test("right edge: docks flush to the right, half width, full height")
    func rightEdge() {
        let frames = FloatingPanePlacement.frames(
            edge: .right,
            visibleFrame: Self.visibleFrame,
            extentRatio: 0.5
        )

        #expect(frames.onscreen.size == frames.offscreen.size)
        #expect(frames.onscreen.height == Self.visibleFrame.height)
        #expect(frames.onscreen.width == Self.visibleFrame.width * 0.5)
        #expect(frames.onscreen.minY == Self.visibleFrame.minY)
        #expect(frames.onscreen.maxX == Self.visibleFrame.maxX)

        #expect(frames.offscreen.minX == Self.visibleFrame.maxX)
        #expect(!Self.visibleFrame.intersects(frames.offscreen))
    }

    @Test("a smaller extent ratio shrinks only the perpendicular dimension")
    func extentRatioAffectsOnlyPerpendicularDimension() {
        let frames = FloatingPanePlacement.frames(
            edge: .top,
            visibleFrame: Self.visibleFrame,
            extentRatio: 0.25
        )

        #expect(frames.onscreen.height == Self.visibleFrame.height * 0.25)
        #expect(frames.onscreen.width == Self.visibleFrame.width)
    }

    @Test("falls back to the main screen when no screen contains the mouse")
    func targetScreenFallsBackToMainScreen() {
        let farAwayPoint = NSPoint(x: -1_000_000, y: -1_000_000)
        let result = FloatingPanePlacement.targetScreen(
            screens: NSScreen.screens,
            mouseLocation: farAwayPoint,
            mainScreen: NSScreen.main
        )
        #expect(result === NSScreen.main)
    }

    @Test("picks the screen whose frame contains the point")
    func targetScreenPicksContainingScreen() throws {
        let screen = try #require(NSScreen.main)
        let insideMainScreen = NSPoint(
            x: screen.frame.midX,
            y: screen.frame.midY
        )
        let result = FloatingPanePlacement.targetScreen(
            screens: NSScreen.screens,
            mouseLocation: insideMainScreen,
            mainScreen: nil
        )
        #expect(result === screen)
    }
}
