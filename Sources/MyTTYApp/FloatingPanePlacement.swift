import AppKit
import MyTTYCore

/// Pure placement math for the floating terminal panel's Quake-style
/// slide-in (issue #103): where it sits off-screen before the animation and
/// where it docks against the chosen edge once on-screen. Kept as static
/// functions, same shape as `PaneListWindowPlacement.centeredFrame`
/// (`PaneListWindowController.swift:7-17`), so the geometry is testable
/// without a live `NSPanel`.
enum FloatingPanePlacement {
    /// The panel's on-screen size for `edge`: the full width (top/bottom) or
    /// full height (left/right) of `visibleFrame`, and `extentRatio` of the
    /// perpendicular dimension.
    static func size(
        edge: FloatingPaneEdge,
        visibleFrame: NSRect,
        extentRatio: CGFloat
    ) -> NSSize {
        switch edge {
        case .top, .bottom:
            NSSize(
                width: visibleFrame.width,
                height: visibleFrame.height * extentRatio
            )
        case .left, .right:
            NSSize(
                width: visibleFrame.width * extentRatio,
                height: visibleFrame.height
            )
        }
    }

    /// The off-screen (`offscreen`, staged just past `edge` before sliding
    /// in) and on-screen (`onscreen`, docked flush against `edge`) frames
    /// for the panel. Both share the size returned by `size(edge:visibleFrame:extentRatio:)`
    /// — the slide animation only ever moves the origin, never resizes the
    /// window, so the terminal underneath is never asked to resize mid-slide.
    static func frames(
        edge: FloatingPaneEdge,
        visibleFrame: NSRect,
        extentRatio: CGFloat = 0.5
    ) -> (offscreen: NSRect, onscreen: NSRect) {
        let paneSize = size(
            edge: edge,
            visibleFrame: visibleFrame,
            extentRatio: extentRatio
        )
        switch edge {
        case .top:
            let onscreenOrigin = NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - paneSize.height
            )
            let offscreenOrigin = NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.maxY
            )
            return (
                NSRect(origin: offscreenOrigin, size: paneSize),
                NSRect(origin: onscreenOrigin, size: paneSize)
            )
        case .bottom:
            let onscreenOrigin = NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.minY
            )
            let offscreenOrigin = NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.minY - paneSize.height
            )
            return (
                NSRect(origin: offscreenOrigin, size: paneSize),
                NSRect(origin: onscreenOrigin, size: paneSize)
            )
        case .left:
            let onscreenOrigin = NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.minY
            )
            let offscreenOrigin = NSPoint(
                x: visibleFrame.minX - paneSize.width,
                y: visibleFrame.minY
            )
            return (
                NSRect(origin: offscreenOrigin, size: paneSize),
                NSRect(origin: onscreenOrigin, size: paneSize)
            )
        case .right:
            let onscreenOrigin = NSPoint(
                x: visibleFrame.maxX - paneSize.width,
                y: visibleFrame.minY
            )
            let offscreenOrigin = NSPoint(
                x: visibleFrame.maxX,
                y: visibleFrame.minY
            )
            return (
                NSRect(origin: offscreenOrigin, size: paneSize),
                NSRect(origin: onscreenOrigin, size: paneSize)
            )
        }
    }

    /// The screen the panel should appear on: whichever screen contains the
    /// mouse cursor, falling back to the main screen when that can't be
    /// determined (e.g. in a headless test environment).
    static func targetScreen(
        screens: [NSScreen],
        mouseLocation: NSPoint,
        mainScreen: NSScreen?
    ) -> NSScreen? {
        screens.first { $0.frame.contains(mouseLocation) } ?? mainScreen
    }
}
