import AppKit
import GhosttyAdapter
import MyTTYCore

/// Owns the standalone Quake-style floating terminal panel (issue #103): a
/// single terminal surface in its own `NSPanel` that slides in from a
/// screen edge on a global hot key, for quick throwaway work without
/// touching the split-pane layout of any real window.
///
/// Deliberately never registers with `TerminalWindowController.surfaces` or
/// `session.tabs` -- those two collections are what every excluded feature
/// (session persistence, iOS remote visibility, mytty-ctl pane listing,
/// agent status/usage polling, Attention, autocomplete) enumerates from, so
/// staying out of both satisfies every exclusion without a single `if`
/// checking for "is this the floating pane". `environmentVariables: [:]` is
/// the same mechanism applied to the shell itself: no `MYTTY_*` variables
/// means no hook, no `AgentEventServer` registration, nothing for an agent
/// or `mytty-ctl` to find.
///
/// Structure follows `InputComposerPanelController` (`InputComposerPanel.swift:25`):
/// a plain `NSPanel`, built once, shown and hidden rather than
/// created/destroyed per use. `becomesKeyOnlyIfNeeded` is deliberately not
/// set, unlike `PaneExplanation.swift:98` -- a terminal needs real keyboard
/// focus, not just enough to dismiss itself.
/// A borderless panel that still takes keyboard focus. `NSWindow` refuses
/// key status to borderless windows by default, which for a terminal would
/// mean a panel that looks focused and swallows nothing.
final class FloatingTerminalPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Decides whether opening the floating panel should force an ASCII input
/// source, mirroring the scope rule `TerminalWindowController` applies to
/// its own surfaces. Pure, so the rule is testable without touching the
/// system's input sources.
enum FloatingPaneASCIIInputPolicy {
    static func shouldForceASCII(
        enabled: Bool,
        scope: ForceASCIIInputScope,
        shellIsFresh: Bool,
        foregroundCommandName: String?
    ) -> Bool {
        guard enabled else { return false }
        guard scope == .shellIdleOnly else { return true }
        // A shell built moments ago has nothing running in it yet, and its
        // foreground process usually can't be read back this early -- the
        // one case where "no readable foreground process" means idle rather
        // than unknown.
        if shellIsFresh { return true }
        guard let foregroundCommandName else { return false }
        return TerminalAgentProcessDetector.isShellCommandName(
            foregroundCommandName
        )
    }
}

@MainActor
final class FloatingTerminalPanelController: NSObject, NSWindowDelegate {
    private static let animationDuration: TimeInterval = 0.16
    private static let defaultExtentRatio: CGFloat = 0.5
    private static let minimumExtentRatio: CGFloat = 0.15

    /// How the panel's frame moves from wherever it is now to `frame`,
    /// then calls `completion`. Real usage animates via
    /// `NSAnimationContext` (`coreAnimationFrameAnimator`); tests inject a
    /// synchronous variant instead, since a real Core Animation completion
    /// callback rides on an actual display refresh that a headless test
    /// process can't reliably drive on a deadline.
    typealias FrameAnimator = (
        _ panel: NSPanel,
        _ frame: NSRect,
        _ completion: @escaping @MainActor () -> Void
    ) -> Void

    /// Animates only the window's origin between two frames of identical
    /// size (`FloatingPanePlacement.frames` guarantees this), so
    /// `ghostty_surface_set_size` never fires mid-slide -- resizing the
    /// terminal every animation frame would be needless work the animation
    /// doesn't need.
    static let coreAnimationFrameAnimator: FrameAnimator = {
        panel, frame, completion in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingTerminalPanelController.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                completion()
            }
        }
    }

    private let panel: NSPanel
    private var localizer: MyTTYLocalizer
    private let runtimeProvider: () -> GhosttyRuntime?
    private let frameAnimator: FrameAnimator
    private var surface: GhosttySurfaceView?
    private var edge: FloatingPaneEdge
    private var forceASCIIInputOnFocus: Bool
    private var forceASCIIInputScope: ForceASCIIInputScope
    /// Fraction of the screen's perpendicular dimension the panel occupies.
    /// Kept for the process's lifetime only -- never written to disk, per
    /// the spec's "don't persist a dimension the user only nudged for this
    /// session".
    private var extentRatio = FloatingTerminalPanelController.defaultExtentRatio
    /// Whether a slide-out is in flight. `panel.isVisible` alone can't say:
    /// it stays `true` for the whole slide-out and only drops on the final
    /// `orderOut`. Everything else about "is the panel open" is read from
    /// `panel.isVisible` rather than tracked separately, so the panel
    /// disappearing by some route other than `toggle()` -- `orderOut` after
    /// the shell exits, say -- can't leave a stale flag that makes the next
    /// hot key press slide out something already gone.
    private var isSlidingOut = false
    /// Discards a stale animation's completion handler when a later
    /// `toggle()` retargets the same window property mid-flight.
    private var animationGeneration = 0

    init(
        localizer: MyTTYLocalizer,
        edge: FloatingPaneEdge,
        forceASCIIInputOnFocus: Bool = false,
        forceASCIIInputScope: ForceASCIIInputScope = .shellIdleOnly,
        runtimeProvider: @escaping () -> GhosttyRuntime?,
        frameAnimator: @escaping FrameAnimator = coreAnimationFrameAnimator
    ) {
        self.localizer = localizer
        self.edge = edge
        self.forceASCIIInputOnFocus = forceASCIIInputOnFocus
        self.forceASCIIInputScope = forceASCIIInputScope
        self.runtimeProvider = runtimeProvider
        self.frameAnimator = frameAnimator

        // Borderless, so the terminal runs flush to the screen edge with no
        // title bar band between them -- a drop-down console, not a
        // document window. There is no close button to lose: the hot key
        // both summons and dismisses the panel.
        panel = FloatingTerminalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.title = localizer[.floatingPane]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        // AppKit's own deactivate-hide would snap the panel away with no
        // slide-out; `windowDidResignKey` below covers the same "focus left
        // the panel" case (another app activating included) with the same
        // animated `hide()` a hot key press uses, so there's nothing left
        // for the built-in behavior to do.
        panel.hidesOnDeactivate = false
        TerminalWindowController.prepareWindowForLiveTransparency(panel)

        super.init()
        panel.delegate = self
    }

    func updateLocalization(_ localizer: MyTTYLocalizer) {
        self.localizer = localizer
        panel.title = localizer[.floatingPane]
    }

    /// Applies a new dock edge. Deferred while the panel is open so a
    /// settings change never yanks a visible panel to a different edge and
    /// size out from under the user -- it takes effect the next time the
    /// panel opens.
    func updateEdge(_ edge: FloatingPaneEdge) {
        guard edge != self.edge else { return }
        self.edge = edge
        if !panel.isVisible {
            extentRatio = Self.defaultExtentRatio
        }
    }

    func updateASCIIInput(
        onFocus: Bool,
        scope: ForceASCIIInputScope
    ) {
        forceASCIIInputOnFocus = onFocus
        forceASCIIInputScope = scope
    }

    /// Slides the panel in if it's closed, out if it's open. Safe to call
    /// mid-animation: the in-flight slide reverses direction from wherever
    /// it currently is instead of snapping first.
    func toggle() {
        if !panel.isVisible || isSlidingOut {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard let frames = targetFrames() else { return }
        isSlidingOut = false
        let shellIsFresh = surface == nil
        ensureSurface()
        // Only jump to the staged off-screen frame when actually starting
        // from closed. Reversing a slide-out mid-flight must resume from
        // the window's current (still visible) frame, not reset first.
        if !panel.isVisible {
            panel.setFrame(frames.offscreen, display: false)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        forceASCIIInputIfNeeded(shellIsFresh: shellIsFresh)
        // Key status is taken before the slide, not in its completion
        // handler: an `NSWindow` frame animation's completion is not a
        // dependable place to hang it on, and when it doesn't run the panel
        // sits there looking focused while every keystroke goes to whatever
        // window actually holds focus.
        //
        // Activating the app is asynchronous and hands key status back to
        // the window that last held it, so the panel has to claim it again
        // once that has settled. Doing it twice -- now and on the next turn
        // of the run loop -- covers both the already-active case (where
        // there is nothing to wait for) and the summoned-from-another-app
        // case.
        takeKeyFocus()
        DispatchQueue.main.async { [weak self] in
            self?.takeKeyFocus()
        }
        animate(to: frames.onscreen) {}
    }

    private func takeKeyFocus() {
        guard !isSlidingOut else { return }
        panel.makeKeyAndOrderFront(nil)
        if let surface {
            panel.makeFirstResponder(surface)
        }
    }

    /// Switches the input source to an ASCII-capable one as the panel takes
    /// focus. `TerminalWindowController` does the same for its own surfaces
    /// (`evaluateASCIIInputForActivePane`) but can't cover this one, which
    /// isn't in its `surfaces`. The global hot key makes it matter more
    /// here: the panel is routinely summoned from another app, and whatever
    /// IME that app was using would otherwise still be active at the prompt.
    private func forceASCIIInputIfNeeded(shellIsFresh: Bool) {
        let foregroundCommandName = surface.flatMap {
            TerminalAgentProcessDetector.commandName(
                processID: $0.foregroundProcessID
            )
        }
        guard FloatingPaneASCIIInputPolicy.shouldForceASCII(
            enabled: forceASCIIInputOnFocus,
            scope: forceASCIIInputScope,
            shellIsFresh: shellIsFresh,
            foregroundCommandName: foregroundCommandName
        ) else { return }
        ASCIIInputSourceSwitcher.switchToASCIIIfNeeded()
    }

    private func hide() {
        guard let frames = targetFrames() else {
            panel.orderOut(nil)
            return
        }
        isSlidingOut = true
        animate(to: frames.offscreen) { [weak self] in
            guard let self else { return }
            isSlidingOut = false
            panel.orderOut(nil)
        }
    }

    private func targetFrames() -> (offscreen: NSRect, onscreen: NSRect)? {
        guard let screen = FloatingPanePlacement.targetScreen(
            screens: NSScreen.screens,
            mouseLocation: NSEvent.mouseLocation,
            mainScreen: NSScreen.main
        ) else { return nil }
        return FloatingPanePlacement.frames(
            edge: edge,
            visibleFrame: screen.visibleFrame,
            extentRatio: extentRatio
        )
    }

    /// Runs `frameAnimator` and discards its completion if a later
    /// `animate(to:completion:)` call has since superseded it -- the
    /// generation counter is what actually implements "an in-flight slide
    /// reverses instead of both animations finishing and fighting over the
    /// final state".
    private func animate(
        to frame: NSRect,
        completion: @escaping () -> Void
    ) {
        animationGeneration += 1
        let generation = animationGeneration
        frameAnimator(panel, frame) { [weak self] in
            guard let self, generation == animationGeneration else { return }
            completion()
        }
    }

    /// Creates the terminal surface on first use and keeps it alive across
    /// hide/show cycles -- the shell underneath survives an `orderOut`, per
    /// the spec's "closing is `orderOut` only, no persistence".
    private func ensureSurface() {
        guard surface == nil, let runtime = runtimeProvider() else { return }
        guard let created = try? GhosttySurfaceView(
            runtime: runtime,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            environmentVariables: [:],
            searchLabels: makeSearchLabels(),
            contextMenuLabels: makeContextMenuLabels(),
            clipboardConfirmationLabels: makeClipboardConfirmationLabels()
        ) else { return }
        // The panel has no status bar to list bookmarks in, so don't
        // offer the context-menu action here.
        created.contextMenuIncludesAddBookmark = false
        bind(created)
        panel.contentView = created
        surface = created
    }

    private func bind(_ surface: GhosttySurfaceView) {
        surface.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: GhosttySurfaceEvent) {
        switch event {
        case .childExited, .closeRequested(processAlive: false):
            destroySurfaceAndHide()
        case let .openURLRequested(url):
            NSWorkspace.shared.open(url)
        case .newTabRequested, .closeTabRequested, .newWindowRequested,
             .movePaneRequested, .closePaneRequested:
            // No tabs or sibling panes exist in this standalone panel.
            break
        default:
            break
        }
    }

    /// The shell exited on its own (e.g. `exit`, or the process died).
    /// Unlike a user-initiated `toggle()`, there's no shell left to keep
    /// alive, so the surface is torn down immediately rather than staying
    /// around for a hide/show cycle -- the next `show()` builds a fresh one.
    private func destroySurfaceAndHide() {
        surface?.onEvent = nil
        surface?.removeFromSuperview()
        surface = nil
        panel.contentView = nil
        isSlidingOut = false
        panel.orderOut(nil)
    }

    private func makeSearchLabels() -> GhosttySearchLabels {
        GhosttySearchLabels(
            placeholder: localizer[.search],
            previousMatch: localizer[.previousMatch],
            nextMatch: localizer[.nextMatch],
            closeSearch: localizer[.closeSearch]
        )
    }

    private func makeContextMenuLabels() -> GhosttyContextMenuLabels {
        GhosttyContextMenuLabels(
            copy: localizer[.copy],
            paste: localizer[.paste],
            selectAll: localizer[.selectAll],
            lookUpSelectionFormat: localizer[.lookUpSelectionFormat],
            searchWithGoogle: localizer[.searchWithGoogle],
            share: localizer[.share],
            services: localizer[.services],
            moveToTab: localizer[.moveToTab],
            closePane: localizer[.closePane],
            addBookmark: localizer[.addBookmark]
        )
    }

    private func makeClipboardConfirmationLabels()
        -> GhosttyClipboardConfirmationLabels
    {
        GhosttyClipboardConfirmationLabels(
            title: localizer[.unsafePasteTitle],
            message: localizer[.unsafePasteMessage],
            pasteButton: localizer[.paste],
            cancelButton: localizer[.cancel]
        )
    }

    // MARK: - NSWindowDelegate

    /// Only the dimension perpendicular to the docked edge is meaningful to
    /// resize by hand -- the parallel one stays pinned to the full screen
    /// extent (e.g. dragging a top-docked panel's bottom edge changes its
    /// height, but its width always fills the screen).
    func windowWillResize(
        _ sender: NSWindow,
        to frameSize: NSSize
    ) -> NSSize {
        guard let screen = sender.screen else { return frameSize }
        var size = frameSize
        switch edge {
        case .top, .bottom:
            size.width = screen.visibleFrame.width
        case .left, .right:
            size.height = screen.visibleFrame.height
        }
        return size
    }

    func windowDidResize(_ notification: Notification) {
        guard let screen = panel.screen else { return }
        let ratio: CGFloat
        switch edge {
        case .top, .bottom:
            ratio = panel.frame.height / screen.visibleFrame.height
        case .left, .right:
            ratio = panel.frame.width / screen.visibleFrame.width
        }
        guard ratio.isFinite else { return }
        extentRatio = min(max(ratio, Self.minimumExtentRatio), 1)
    }

    /// Slides the panel back out the moment it stops being key -- clicking
    /// another window, Cmd-Tabbing to another app, or the global hot key's
    /// own `hide()` all resign key before the panel disappears. The
    /// in-flight guard matters for that last case: `hide()` already calls
    /// `panel.orderOut(nil)`, which resigns key on its way out, and without
    /// it this would re-enter `hide()` on a panel already sliding away.
    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible, !isSlidingOut else { return }
        hide()
    }

    /// Whether the panel is the app's key window right now. `AppDelegate`
    /// consults this to gate split/pane/tab shortcuts (see
    /// `FloatingPaneCommandAvailability`) so they don't reach a real
    /// terminal window sitting behind this one.
    var isKeyWindow: Bool {
        panel === NSApplication.shared.keyWindow
    }

    // MARK: - Test seams

    var isPanelVisible: Bool { panel.isVisible }
    var hasLiveSurface: Bool { surface != nil }

    /// Hides the panel the way something other than `toggle()` would -- the
    /// shell exiting, AppKit ordering it out -- so a test can check that the
    /// next hot key press still reopens it.
    func simulateExternalHide() {
        panel.orderOut(nil)
    }
}
