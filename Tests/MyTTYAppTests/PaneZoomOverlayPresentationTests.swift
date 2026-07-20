import AppKit
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Pane zoom overlay presentation")
struct PaneZoomOverlayPresentationTests {
    @Test("keeps other panes attached while pane zoom toggles")
    @MainActor
    func paneZoomPreservesOtherPaneContent() {
        let surfaceHost = NSView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 600)
        )
        let splitRoot = NSView(frame: surfaceHost.bounds)
        let leftContent = NSView()
        let rightContent = NSView()
        let leftHost = PaneHostView(content: leftContent)
        let rightHost = PaneHostView(content: rightContent)
        let leftID = TerminalSurfaceID()

        splitRoot.addSubview(leftHost)
        splitRoot.addSubview(rightHost)
        surfaceHost.addSubview(splitRoot)

        let presentation = PaneZoomOverlayPresentation()
        presentation.show(
            paneID: leftID,
            content: leftContent,
            originalHost: leftHost,
            in: surfaceHost
        )

        #expect(presentation.paneID == leftID)
        #expect(leftContent.superview !== leftHost)
        #expect(rightContent.superview === rightHost)
        #expect(rightHost.superview === splitRoot)
        #expect(splitRoot.superview === surfaceHost)

        presentation.dismiss()

        #expect(presentation.paneID == nil)
        #expect(leftContent.superview === leftHost)
        #expect(rightContent.superview === rightHost)
        #expect(rightHost.superview === splitRoot)
        #expect(splitRoot.superview === surfaceHost)
    }
}
