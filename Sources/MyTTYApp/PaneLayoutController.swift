import AppKit
import GhosttyAdapter
import MyTTYCore

/// Owns the live pane tree for the selected tab: the `PaneHostView`s built
/// from a tab's `SplitNode`, the zoom-overlay presentation, and the
/// per-pane focus/dimming/size-indicator bookkeeping. Extracted from
/// `TerminalWindowController.makeSplitView` /
/// `updatePaneZoomPresentation` / `updatePaneFocus` /
/// `updateInactivePaneDimming` / `updatePaneSizeIndicators` /
/// `setPaneSizeIndicatorsVisible` / `showPaneSizeIndicatorsTemporarily`
/// verbatim.
///
/// `attachSelectedTab` itself — the surfaceHost subview-tree rebuild that
/// decides *when* to call `makeSplitView`/`updateZoomPresentation`, plus
/// `renderedTabID`/`isAttachingSelectedTab` bookkeeping — stays on
/// `TerminalWindowController`: it is intertwined with `sessionDidChange`/
/// `refreshPresentation` orchestration and the static chrome helpers
/// (`claimRender`, `finalizePaneAttachment`) that this phase leaves in
/// place. Likewise `equalizePanes`/`togglePaneZoom` stay on the controller
/// as thin wrappers because they mutate `WindowSession`, which this
/// coordinator does not reach into; they delegate the zoom-state and
/// size-indicator bookkeeping here.
///
/// `TerminalWindowController` owns this coordinator and supplies live
/// `surfaces`/`browsers` lookups and the inactive-dimming preference via
/// closures (all controller-private) rather than this type reaching into
/// it directly. `surfaceHost` is handed in once at construction since it
/// is a fixed `NSView` instance for the controller's lifetime.
@MainActor
final class PaneLayoutController {
    private(set) var paneHosts: [TerminalSurfaceID: PaneHostView] = [:]
    private var zoomState = PaneZoomState()
    private let zoomPresentation = PaneZoomOverlayPresentation()
    private var sizeIndicatorHideTask: Task<Void, Never>?

    private let surfaceHost: NSView
    private let surfaces: () -> [TerminalSurfaceID: GhosttySurfaceView]
    private let browsers: () -> [TerminalSurfaceID: BrowserPaneView]
    private let inactivePaneDimming: () -> CGFloat
    private let activePaneBorder: () -> PaneActiveBorderStyle
    private let isLiveResizing: () -> Bool
    private let onRatioChanged: (Double, [SplitPathComponent]) -> Void
    /// Fired whenever the visible size indicators change — the controller
    /// uses this to refresh the status bar, mirroring the trailing
    /// `updateStatusBar()` call at the end of the original
    /// `updatePaneSizeIndicators`.
    private let onSizeIndicatorsChanged: () -> Void

    init(
        surfaceHost: NSView,
        surfaces: @escaping () -> [TerminalSurfaceID: GhosttySurfaceView],
        browsers: @escaping () -> [TerminalSurfaceID: BrowserPaneView],
        inactivePaneDimming: @escaping () -> CGFloat,
        activePaneBorder: @escaping () -> PaneActiveBorderStyle,
        isLiveResizing: @escaping () -> Bool,
        onRatioChanged: @escaping (Double, [SplitPathComponent]) -> Void,
        onSizeIndicatorsChanged: @escaping () -> Void
    ) {
        self.surfaceHost = surfaceHost
        self.surfaces = surfaces
        self.browsers = browsers
        self.inactivePaneDimming = inactivePaneDimming
        self.activePaneBorder = activePaneBorder
        self.isLiveResizing = isLiveResizing
        self.onRatioChanged = onRatioChanged
        self.onSizeIndicatorsChanged = onSizeIndicatorsChanged
    }

    // MARK: - Zoom state

    @discardableResult
    func toggleZoom(for tab: TabSession) -> Bool {
        zoomState.toggle(for: tab)
    }

    @discardableResult
    func synchronizeZoom(with tab: TabSession) -> Bool {
        zoomState.synchronize(with: tab)
    }

    func zoomTarget(for tab: TabSession) -> TerminalSurfaceID? {
        zoomState.target(for: tab)
    }

    func removeZoom(tabID: TabID) {
        zoomState.remove(tabID: tabID)
    }

    var zoomedPaneID: TerminalSurfaceID? { zoomPresentation.paneID }
    var zoomedHost: PaneHostView? { zoomPresentation.zoomedHost }

    @discardableResult
    func dismissZoomPresentation() -> Bool {
        zoomPresentation.dismiss()
    }

    // MARK: - Pane tree

    func host(for surfaceID: TerminalSurfaceID) -> PaneHostView? {
        paneHosts[surfaceID]
    }

    func resetHosts() {
        paneHosts.removeAll()
    }

    func makeSplitView(
        _ node: SplitNode,
        path: [SplitPathComponent]
    ) -> NSView? {
        switch node {
        case let .surface(state):
            guard let surface = surfaces()[state.id] else { return nil }
            surface.removeFromSuperview()
            let pane = PaneHostView(content: surface)
            pane.updateInactiveDimming(inactivePaneDimming())
            paneHosts[state.id] = pane
            return pane

        case let .browser(state):
            guard let browser = browsers()[state.id] else { return nil }
            browser.removeFromSuperview()
            let pane = PaneHostView(content: browser)
            pane.updateInactiveDimming(inactivePaneDimming())
            paneHosts[state.id] = pane
            return pane

        case let .split(orientation, ratio, first, second):
            guard let firstView = makeSplitView(
                first,
                path: path + [.first]
            ), let secondView = makeSplitView(
                second,
                path: path + [.second]
            ) else { return nil }
            let split = RatioSplitView(
                orientation: orientation,
                ratio: ratio,
                onRatioChanged: { [weak self] ratio in
                    self?.onRatioChanged(ratio, path)
                },
                onUserResize: { [weak self] in
                    self?.showSizeIndicatorsTemporarily()
                }
            )
            split.addArrangedSubview(firstView)
            split.addArrangedSubview(secondView)
            return split
        }
    }

    @discardableResult
    func updateZoomPresentation(for tab: TabSession) -> Bool {
        guard let paneID = zoomState.target(for: tab) else {
            return zoomPresentation.dismiss()
        }
        guard zoomPresentation.paneID != paneID,
              let pane = paneHosts[paneID]
        else { return false }

        let content: NSView? = surfaces()[paneID] ?? browsers()[paneID]
        guard let content else { return false }
        let shown = zoomPresentation.show(
            paneID: paneID,
            content: content,
            originalHost: pane,
            in: surfaceHost
        )
        if shown {
            // The overlay builds a fresh host, so it starts with the
            // defaults rather than the configured appearance.
            zoomPresentation.zoomedHost?
                .updateInactiveDimming(inactivePaneDimming())
            updateActiveBorder()
        }
        return shown
    }

    // MARK: - Focus / dimming / size indicators

    func updateFocus(focusedID: TerminalSurfaceID?) {
        for (surfaceID, surface) in surfaces() {
            surface.setFocused(surfaceID == focusedID)
        }
        for (surfaceID, pane) in paneHosts {
            pane.isFocused = surfaceID == focusedID
        }
        zoomPresentation.zoomedHost?.isFocused = true
        updateActiveBorder()
    }

    /// Highlights the pane picked as the first side of a pending swap, or
    /// clears the highlight when `id` is nil.
    func updateSwapCandidate(_ id: TerminalSurfaceID?) {
        for (surfaceID, pane) in paneHosts {
            pane.isSwapCandidate = surfaceID == id
        }
        zoomPresentation.zoomedHost?.isSwapCandidate =
            id != nil && zoomPresentation.paneID == id
    }

    /// Highlights the pane currently targeted by arrow-key navigation while
    /// picking a pane to swap, or clears it when `id` is nil.
    func updateSwapCursor(_ id: TerminalSurfaceID?) {
        for (surfaceID, pane) in paneHosts {
            pane.isSwapCursor = surfaceID == id
        }
        zoomPresentation.zoomedHost?.isSwapCursor =
            id != nil && zoomPresentation.paneID == id
    }

    /// Shows the click-catching overlay on every live pane, wiring each
    /// one's clicks back to `onPaneClicked` with its own ID.
    func enableSwapClickCatchers(
        onPaneClicked: @escaping (TerminalSurfaceID) -> Void
    ) {
        for (surfaceID, pane) in paneHosts {
            pane.enableSwapClickCatcher { onPaneClicked(surfaceID) }
        }
        if let zoomedHost = zoomPresentation.zoomedHost,
           let zoomedID = zoomPresentation.paneID {
            zoomedHost.enableSwapClickCatcher { onPaneClicked(zoomedID) }
        }
    }

    func disableSwapClickCatchers() {
        paneHosts.values.forEach { $0.disableSwapClickCatcher() }
        zoomPresentation.zoomedHost?.disableSwapClickCatcher()
    }

    func updateInactiveDimming() {
        let amount = inactivePaneDimming()
        paneHosts.values.forEach { $0.updateInactiveDimming(amount) }
        zoomPresentation.zoomedHost?.updateInactiveDimming(amount)
    }

    /// Pushes the configured focus outline to every live host. Called after
    /// the pane tree changes — the "only when split" rule depends on the
    /// final pane count, which `makeSplitView` does not yet know — and
    /// whenever the preference changes.
    func updateActiveBorder() {
        let style = activePaneBorder().effective(paneCount: paneHosts.count)
        paneHosts.values.forEach { $0.activeBorder = style }
        zoomPresentation.zoomedHost?.activeBorder = style
    }

    func updateSizeIndicators() {
        surfaceHost.layoutSubtreeIfNeeded()
        let surfaces = surfaces()
        for (surfaceID, pane) in paneHosts {
            guard let surface = surfaces[surfaceID] else { continue }
            let grid = surface.terminalGridSize
            pane.updateSizeIndicator(
                columns: grid.columns,
                rows: grid.rows
            )
            if zoomPresentation.paneID == surfaceID {
                zoomPresentation.zoomedHost?.updateSizeIndicator(
                    columns: grid.columns,
                    rows: grid.rows
                )
            }
        }
        onSizeIndicatorsChanged()
    }

    func setSizeIndicatorsVisible(_ visible: Bool) {
        let surfaces = surfaces()
        for (surfaceID, pane) in paneHosts {
            pane.setSizeIndicatorVisible(
                visible && surfaces[surfaceID] != nil
            )
            if zoomPresentation.paneID == surfaceID {
                zoomPresentation.zoomedHost?.setSizeIndicatorVisible(
                    visible && surfaces[surfaceID] != nil
                )
            }
        }
    }

    func cancelSizeIndicatorHideTask() {
        sizeIndicatorHideTask?.cancel()
    }

    func showSizeIndicatorsTemporarily() {
        updateSizeIndicators()
        setSizeIndicatorsVisible(true)
        guard !isLiveResizing() else { return }

        sizeIndicatorHideTask?.cancel()
        sizeIndicatorHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.setSizeIndicatorsVisible(false)
        }
    }

    // MARK: - Key toast

    func hideKeyToasts() {
        paneHosts.values.forEach { $0.hideKeyToast() }
        zoomPresentation.zoomedHost?.hideKeyToast()
    }
}
