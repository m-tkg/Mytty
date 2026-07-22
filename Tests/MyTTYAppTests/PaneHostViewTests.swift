import AppKit
import Testing

@testable import MyTTYApp

@Suite("Pane host view")
struct PaneHostViewTests {
    @Test("dims only an inactive pane")
    @MainActor
    func inactivePaneAppearance() {
        let pane = PaneHostView(content: NSView())

        pane.isFocused = false
        #expect(pane.isDimmed)
        #expect(pane.inactiveDimmingAlpha == 0.32)
        #expect(pane.focusBorderWidth == 0)

        pane.isFocused = true
        #expect(!pane.isDimmed)
        #expect(pane.focusBorderWidth == 0)

        pane.updateInactiveDimming(0.55)
        #expect(pane.inactiveDimmingAlpha == 0.55)
    }

    @Test("outlines only the focused pane while the border is configured")
    @MainActor
    func activePaneBorder() {
        let pane = PaneHostView(content: NSView())
        pane.activeBorder = PaneActiveBorderStyle(
            width: 2,
            colorHex: "FF0000"
        )

        #expect(pane.focusBorderWidth == 0)

        pane.isFocused = true
        #expect(pane.focusBorderWidth == 2)
        #expect(pane.focusBorderColor?.redComponent == 1)

        pane.activeBorder = .hidden
        #expect(pane.focusBorderWidth == 0)
    }

    @Test("prefers the swap highlight over the focus border")
    @MainActor
    func swapHighlightOutranksActiveBorder() {
        let pane = PaneHostView(content: NSView())
        pane.activeBorder = PaneActiveBorderStyle(width: 1, colorHex: "")
        pane.isFocused = true
        #expect(pane.focusBorderWidth == 1)

        pane.isSwapCursor = true
        #expect(pane.focusBorderWidth == 2)

        pane.isSwapCandidate = true
        #expect(pane.focusBorderWidth == 3)

        pane.isSwapCandidate = false
        pane.isSwapCursor = false
        #expect(pane.focusBorderWidth == 1)
    }

    @Test("outlines a pane only once the tab is split")
    func activeBorderNeedsMoreThanOnePane() {
        let style = PaneActiveBorderStyle(width: 2, colorHex: "")
        #expect(style.effective(paneCount: 1) == .hidden)
        #expect(style.effective(paneCount: 2) == style)
        #expect(PaneActiveBorderStyle.hidden.effective(paneCount: 4) == .hidden)
    }

    @Test("shows terminal dimensions in the center overlay")
    @MainActor
    func paneSizeIndicator() {
        let pane = PaneHostView(content: NSView())

        pane.updateSizeIndicator(columns: 80, rows: 24)
        pane.setSizeIndicatorVisible(true)

        #expect(pane.sizeIndicatorText == "80 x 24")
        #expect(pane.isSizeIndicatorVisible)

        pane.setSizeIndicatorVisible(false)

        #expect(!pane.isSizeIndicatorVisible)
    }

    @Test("shows a pressed key toast immediately below the terminal cursor")
    @MainActor
    func pressedKeyToast() {
        let pane = PaneHostView(content: NSView())
        pane.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        pane.showKeyToast(
            "⌘D",
            below: NSRect(x: 280, y: 240, width: 10, height: 20)
        )

        #expect(pane.keyToastText == "⌘D")
        #expect(pane.isKeyToastVisible)
        #expect(pane.keyToastFrame.maxY == 234)
        #expect(pane.keyToastFrame.midX == 285)

        pane.hideKeyToast()

        #expect(!pane.isKeyToastVisible)
    }

    @Test("keeps a cursor key toast inside the pane edges")
    @MainActor
    func pressedKeyToastEdgePlacement() {
        let pane = PaneHostView(content: NSView())
        pane.frame = NSRect(x: 0, y: 0, width: 300, height: 160)

        pane.showKeyToast(
            "⌘ShiftLongKey",
            below: NSRect(x: 296, y: 2, width: 4, height: 18)
        )

        #expect(pane.keyToastFrame.maxX <= pane.bounds.maxX - 6)
        #expect(pane.keyToastFrame.minY >= pane.bounds.minY + 6)
        #expect(pane.keyToastFrame.minY == 26)
    }

    @Test("tints only a pane created by mytty-ctl orchestration")
    @MainActor
    func orchestrationTint() {
        let pane = PaneHostView(content: NSView())

        #expect(!pane.isOrchestrated)
        #expect(!pane.isOrchestrationTintVisible)

        pane.isOrchestrated = true
        #expect(pane.isOrchestrationTintVisible)
        #expect(pane.orchestrationTintAlpha == 0.08)

        pane.isFocused = true
        #expect(pane.isDimmed == false)
        #expect(pane.isOrchestrationTintVisible)

        pane.isFocused = false
        #expect(pane.isDimmed)
        #expect(pane.isOrchestrationTintVisible)

        pane.isOrchestrated = false
        #expect(!pane.isOrchestrationTintVisible)
    }
}
