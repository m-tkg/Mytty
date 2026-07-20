import AppKit
import MyTTYCore

@MainActor
final class PaneZoomOverlayPresentation {
    private(set) var paneID: TerminalSurfaceID?
    private(set) var zoomedHost: PaneHostView?
    private weak var originalHost: PaneHostView?

    @discardableResult
    func show(
        paneID: TerminalSurfaceID,
        content: NSView,
        originalHost: PaneHostView,
        in surfaceHost: NSView
    ) -> Bool {
        guard self.paneID != paneID else { return false }
        dismiss()
        guard originalHost.contentView === content,
              let detachedContent = originalHost.detachContent()
        else { return false }

        let zoomedHost = PaneHostView(content: detachedContent)
        zoomedHost.isFocused = true
        zoomedHost.translatesAutoresizingMaskIntoConstraints = false
        surfaceHost.addSubview(
            zoomedHost,
            positioned: .above,
            relativeTo: nil
        )
        NSLayoutConstraint.activate([
            zoomedHost.leadingAnchor.constraint(
                equalTo: surfaceHost.leadingAnchor
            ),
            zoomedHost.trailingAnchor.constraint(
                equalTo: surfaceHost.trailingAnchor
            ),
            zoomedHost.topAnchor.constraint(equalTo: surfaceHost.topAnchor),
            zoomedHost.bottomAnchor.constraint(equalTo: surfaceHost.bottomAnchor),
        ])
        self.paneID = paneID
        self.originalHost = originalHost
        self.zoomedHost = zoomedHost
        return true
    }

    @discardableResult
    func dismiss() -> Bool {
        guard paneID != nil else { return false }
        let content = zoomedHost?.detachContent()
        zoomedHost?.removeFromSuperview()
        if let content, let originalHost {
            originalHost.attachContent(content)
        }
        paneID = nil
        zoomedHost = nil
        originalHost = nil
        return true
    }
}
