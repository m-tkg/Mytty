import AppKit
import GhosttyAdapter
import MyTTYRemoteKit

/// Draws a mirrored remote screen on a fixed character grid and turns local
/// keyboard, mouse and scroll events into remote protocol calls.
///
/// This is deliberately *not* a `GhosttySurfaceView`: there is no terminal
/// emulator and no PTY behind it. Everything it shows arrived as styled
/// runs from the host Mac, which is also why it draws on a grid rather than
/// laying text out with wrapping — the host already decided where every
/// cell goes, and re-wrapping here would shear the screen.
@MainActor
final class RemotePaneScreenView: NSView, @preconcurrency NSTextInputClient {
    /// Text typed with no modifiers that the host should insert as typed
    /// keyboard input.
    var onSendText: ((String) -> Void)?
    /// A discrete keystroke: a named key such as "escape"/"up", or a single
    /// character carrying Control/Option, delivered on the host as a real
    /// key event so TUIs using the kitty keyboard protocol see it.
    var onSendKey: ((String, [String]) -> Void)?
    /// Wheel lines for an alternate-screen pane, which has no local
    /// scrollback to move (positive = toward older content).
    var onSendScroll: ((Double) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    /// The IME's in-progress composition, which cannot be drawn into the
    /// mirrored grid (the next frame from the host would wipe it), so the
    /// pane shows it in its own chrome instead.
    var onCompositionChanged: ((String) -> Void)?
    /// A clipboard paste, from the context menu, Edit > Paste, or Cmd+V.
    var onPaste: (() -> Void)?
    /// The user chose "Close Pane" from the context menu.
    var onClosePane: (() -> Void)?
    /// The user chose "Move to Tab" from the context menu, picking one of
    /// the window's other tabs as the destination.
    var onMovePane: ((UUID) -> Void)?
    /// Supplies the "Move to Tab" submenu contents on demand; empty (or
    /// nil) hides the submenu entirely.
    var contextMenuMoveTargets: (() -> [GhosttyContextMenuMoveTarget])?

    private let contextMenuLabels: GhosttyContextMenuLabels
    private var contextMenuLocation = NSPoint.zero
    private var contextMenuSharingPicker: NSSharingServicePicker?

    private(set) var isInputEnabled = false {
        didSet { needsDisplay = true }
    }

    private var lines: [[RemotePaneRun]] = []
    private var plainLines: [String] = []
    private var isAltScreen = false

    private var font: NSFont
    private var boldFont: NSFont
    private var italicFont: NSFont
    private var boldItalicFont: NSFont
    private var cellWidth: CGFloat = 8
    private var lineHeight: CGFloat = 16
    private var baselineOffset: CGFloat = 4

    /// Anchor and head of the current selection in grid coordinates, or nil
    /// when nothing is selected.
    private var selectionAnchor: GridPoint?
    private var selectionHead: GridPoint?

    /// Accumulates sub-line wheel deltas so a trackpad's fine-grained
    /// scrolling still produces whole wheel lines for the host.
    private var scrollRemainder: CGFloat = 0

    private var markedText = ""

    /// Tracks frame changes of the enclosing scroll view's clip view, so a
    /// pane that only got wider (a sibling pane closing, a window resize)
    /// still widens its content. The host only pushes a new snapshot when
    /// the mirrored pane's visible text or cursor actually changes, so a
    /// viewport resize with no new content would otherwise leave
    /// `documentView` frozen at its old, narrower size.
    private var viewportFrameObserver: (any NSObjectProtocol)?

    private struct GridPoint: Equatable, Comparable {
        var row: Int
        var column: Int

        static func < (lhs: GridPoint, rhs: GridPoint) -> Bool {
            lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
        }
    }

    init(
        font: NSFont,
        contextMenuLabels: GhosttyContextMenuLabels = GhosttyContextMenuLabels()
    ) {
        self.font = font
        self.contextMenuLabels = contextMenuLabels
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        italicFont = NSFontManager.shared.convert(
            font,
            toHaveTrait: .italicFontMask
        )
        boldItalicFont = NSFontManager.shared.convert(
            boldFont,
            toHaveTrait: .italicFontMask
        )
        super.init(frame: .zero)
        recomputeMetrics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    isolated deinit {
        stopObservingViewportFrame()
    }

    /// Re-subscribes to the enclosing scroll view's clip view whenever this
    /// view's place in the hierarchy changes (embedding in a scroll view,
    /// moving to a different one, or being torn down), so the observer
    /// never outlives, or misses, the clip view it should be watching.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        stopObservingViewportFrame()
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsFrameChangedNotifications = true
        viewportFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateContentSize()
            }
        }
        // The viewport may already differ from what the last `update` saw
        // (e.g. a sibling pane closed and widened this scroll view before
        // this view was reparented into it), so sync immediately too.
        invalidateContentSize()
    }

    private func stopObservingViewportFrame() {
        if let viewportFrameObserver {
            NotificationCenter.default.removeObserver(viewportFrameObserver)
        }
        viewportFrameObserver = nil
    }

    // MARK: - Content

    func update(font: NSFont) {
        guard font != self.font else { return }
        self.font = font
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        italicFont = NSFontManager.shared.convert(
            font,
            toHaveTrait: .italicFontMask
        )
        boldItalicFont = NSFontManager.shared.convert(
            boldFont,
            toHaveTrait: .italicFontMask
        )
        recomputeMetrics()
        invalidateContentSize()
        needsDisplay = true
    }

    /// Replaces the mirrored screen. `plainText` is kept alongside the
    /// styled runs so copying a selection reproduces exactly what the host
    /// sent, rather than a string reassembled from draw-time runs.
    func update(
        lines: [[RemotePaneRun]],
        plainText: String,
        isAltScreen: Bool
    ) {
        self.lines = lines
        plainLines = plainText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        // Keep the two in step: the renderer pads the styled lines out to
        // the cursor row, and a selection indexing past `plainLines` would
        // otherwise copy nothing for those rows.
        while plainLines.count < lines.count { plainLines.append("") }
        self.isAltScreen = isAltScreen
        clampSelection()
        invalidateContentSize()
        needsDisplay = true
    }

    func setInputEnabled(_ enabled: Bool) {
        guard enabled != isInputEnabled else { return }
        isInputEnabled = enabled
        if !enabled { clearComposition() }
    }

    /// Columns and rows that currently fit the viewport, which the owner
    /// reports to the host so it can size the mirrored pane sensibly.
    var visibleGridSize: (columns: Int, rows: Int) {
        let viewport = enclosingScrollView?.contentView.bounds.size ?? bounds.size
        return (
            max(1, Int(viewport.width / cellWidth)),
            max(1, Int(viewport.height / lineHeight))
        )
    }

    private func recomputeMetrics() {
        let measured = NSAttributedString(
            string: "0",
            attributes: [.font: font]
        ).size().width
        cellWidth = max(1, measured)
        lineHeight = (font.ascender - font.descender + font.leading)
            .rounded(.up)
        baselineOffset = font.ascender.rounded(.up)
    }

    private func invalidateContentSize() {
        let width = CGFloat(widestLine()) * cellWidth
        let height = CGFloat(max(1, lines.count)) * lineHeight
        let viewport = enclosingScrollView?.contentView.bounds.size ?? .zero
        let newSize = NSSize(
            width: max(width, viewport.width),
            height: max(height, viewport.height)
        )
        // `setFrameSize` can flip a scroller's visibility, which resizes
        // the clip view and re-fires the frame-change notification this
        // method is subscribed to; bailing out once the size has settled
        // breaks that loop instead of letting it recurse indefinitely.
        guard newSize != frame.size else { return }
        setFrameSize(newSize)
    }

    private func widestLine() -> Int {
        lines.reduce(0) { widest, runs in
            let width = runs.reduce(0) {
                $0 + RemoteCellWidth.displayWidth($1.text)
            }
            return max(widest, width)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let firstRow = max(0, Int(dirtyRect.minY / lineHeight))
        let lastRow = min(
            lines.count - 1,
            Int(dirtyRect.maxY / lineHeight)
        )
        guard firstRow <= lastRow else { return }

        let selection = normalizedSelection()
        for row in firstRow...lastRow {
            draw(runs: lines[row], row: row, selection: selection)
        }
    }

    private func draw(
        runs: [RemotePaneRun],
        row: Int,
        selection: (start: GridPoint, end: GridPoint)?
    ) {
        let y = CGFloat(row) * lineHeight
        var column = 0

        for run in runs {
            let width = RemoteCellWidth.displayWidth(run.text)
            let rect = NSRect(
                x: CGFloat(column) * cellWidth,
                y: y,
                width: CGFloat(width) * cellWidth,
                height: lineHeight
            )
            let colors = resolvedColors(for: run)
            if let background = colors.background {
                background.setFill()
                rect.fill()
            }
            NSAttributedString(
                string: run.text,
                attributes: attributes(for: run, foreground: colors.foreground)
            ).draw(at: NSPoint(x: rect.minX, y: y))
            column += width
        }

        drawSelection(row: row, y: y, selection: selection, lineEnd: column)
    }

    private func drawSelection(
        row: Int,
        y: CGFloat,
        selection: (start: GridPoint, end: GridPoint)?,
        lineEnd: Int
    ) {
        guard let selection,
              row >= selection.start.row,
              row <= selection.end.row
        else { return }
        let start = row == selection.start.row ? selection.start.column : 0
        // Rows in the middle of a multi-row selection highlight to the end
        // of their own text, not to the widest line, so the block does not
        // look ragged against trailing empty space.
        let end = row == selection.end.row ? selection.end.column : lineEnd
        guard end > start else { return }
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45).setFill()
        NSRect(
            x: CGFloat(start) * cellWidth,
            y: y,
            width: CGFloat(end - start) * cellWidth,
            height: lineHeight
        ).fill(using: .sourceOver)
    }

    private func attributes(
        for run: RemotePaneRun,
        foreground: NSColor
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: self.font(for: run),
            .foregroundColor: foreground,
        ]
        if let underline = Self.underlineStyle(for: run.underline) {
            attributes[.underlineStyle] = underline.rawValue
            // An underline colour the host set apart from the text (SGR 58)
            // is what makes a curly error underline readable; without it
            // AppKit draws the underline in the text colour.
            attributes[.underlineColor] = run.underlineColor
                .map(Self.color(fromRGB:)) ?? foreground
        }
        if run.strikethrough {
            attributes[.strikethroughStyle] =
                NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = foreground
        }
        return attributes
    }

    private func font(for run: RemotePaneRun) -> NSFont {
        switch (run.bold, run.italic) {
        case (true, true): boldItalicFont
        case (true, false): boldFont
        case (false, true): italicFont
        case (false, false): font
        }
    }

    /// AppKit has no dotted or dashed underline, and no curly one below the
    /// patterns it does offer — `patternDot`/`patternDash` are the closest
    /// available, and a curly underline falls back to a plain one rather
    /// than disappearing.
    private static func underlineStyle(
        for style: RemoteUnderlineStyle
    ) -> NSUnderlineStyle? {
        switch style {
        case .none: nil
        case .single: .single
        case .double: .double
        case .curly: .single
        case .dotted: [.single, .patternDot]
        case .dashed: [.single, .patternDash]
        }
    }

    private func resolvedColors(
        for run: RemotePaneRun
    ) -> (foreground: NSColor, background: NSColor?) {
        let foreground = run.foreground.map(Self.color(fromRGB:))
            ?? NSColor.textColor
        let background = run.background.map(Self.color(fromRGB:))
        if run.inverse {
            return (
                background ?? NSColor.textBackgroundColor,
                run.foreground.map(Self.color(fromRGB:)) ?? NSColor.textColor
            )
        }
        // Faint text (SGR 2) renders at reduced intensity, matching how the
        // host draws dimmed hint text.
        return (
            run.faint ? foreground.withAlphaComponent(0.5) : foreground,
            background
        )
    }

    private static func color(fromRGB rgb: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChanged?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            clearComposition()
            onFocusChanged?(false)
        }
        return resigned
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard isInputEnabled else { return }
        // An in-progress composition owns the keyboard until it commits,
        // or the IME loses track of what it is converting.
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        if sendAsNamedKey(event) { return }
        interpretKeyEvents([event])
    }

    /// Sends the event as a discrete keystroke, returning true when it did.
    /// Anything a terminal expects to see as a key press rather than as
    /// inserted text goes this way: named keys, and characters carrying
    /// Control or Option.
    private func sendAsNamedKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Command combos belong to the app's own menus and key bindings.
        if flags.contains(.command) { return false }

        var modifiers: [String] = []
        if flags.contains(.shift) { modifiers.append("shift") }
        if flags.contains(.control) { modifiers.append("control") }
        if flags.contains(.option) { modifiers.append("option") }

        if let named = Self.namedKey(for: event) {
            onSendKey?(named, modifiers.sorted())
            return true
        }
        guard flags.contains(.control) || flags.contains(.option) else {
            return false
        }
        // `charactersIgnoringModifiers` is what names the key: with Option
        // held, `characters` is already the composed symbol (Option-C is
        // "ç"), which the host could not map back to a key code.
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1
        else { return false }
        onSendKey?(characters.lowercased(), modifiers.sorted())
        return true
    }

    private static func namedKey(for event: NSEvent) -> String? {
        if let named = namedKeysByKeyCode[event.keyCode] { return named }
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars
            .first
        else { return nil }
        return namedKeysByFunctionCharacter[scalar]
    }

    /// Virtual key codes whose meaning never changes with the layout.
    private static let namedKeysByKeyCode: [UInt16: String] = [
        53: "escape",
        48: "tab",
        36: "return",
        76: "return",
        51: "delete",
    ]

    /// AppKit reports arrows and function keys as characters in the private
    /// F700 range rather than as stable key codes across layouts.
    private static let namedKeysByFunctionCharacter: [Unicode.Scalar: String] = [
        Unicode.Scalar(UInt16(NSUpArrowFunctionKey))!: "up",
        Unicode.Scalar(UInt16(NSDownArrowFunctionKey))!: "down",
        Unicode.Scalar(UInt16(NSLeftArrowFunctionKey))!: "left",
        Unicode.Scalar(UInt16(NSRightArrowFunctionKey))!: "right",
        Unicode.Scalar(UInt16(NSF1FunctionKey))!: "f1",
        Unicode.Scalar(UInt16(NSF2FunctionKey))!: "f2",
        Unicode.Scalar(UInt16(NSF3FunctionKey))!: "f3",
        Unicode.Scalar(UInt16(NSF4FunctionKey))!: "f4",
        Unicode.Scalar(UInt16(NSF5FunctionKey))!: "f5",
        Unicode.Scalar(UInt16(NSF6FunctionKey))!: "f6",
        Unicode.Scalar(UInt16(NSF7FunctionKey))!: "f7",
        Unicode.Scalar(UInt16(NSF8FunctionKey))!: "f8",
        Unicode.Scalar(UInt16(NSF9FunctionKey))!: "f9",
        Unicode.Scalar(UInt16(NSF10FunctionKey))!: "f10",
        Unicode.Scalar(UInt16(NSF11FunctionKey))!: "f11",
        Unicode.Scalar(UInt16(NSF12FunctionKey))!: "f12",
    ]

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        clearComposition()
        guard isInputEnabled else { return }
        let text: String
        switch string {
        case let value as String: text = value
        case let value as NSAttributedString: text = value.string
        default: return
        }
        guard !text.isEmpty else { return }
        onSendText?(text)
    }

    override func doCommand(by selector: Selector) {
        // Every command a terminal cares about was already sent as a named
        // key in `keyDown`; the rest (text-editing selectors AppKit derives
        // from key bindings) have no meaning for a mirrored screen.
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        switch string {
        case let value as String: markedText = value
        case let value as NSAttributedString: markedText = value.string
        default: markedText = ""
        }
        onCompositionChanged?(markedText)
    }

    func unmarkText() {
        clearComposition()
    }

    private func clearComposition() {
        guard !markedText.isEmpty else { return }
        markedText = ""
        onCompositionChanged?("")
    }

    func selectedRange() -> NSRange {
        NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// Places the IME's candidate window under the pane's cursor. The exact
    /// cursor cell is not tracked locally, so the bottom-left of the
    /// viewport is used — close enough that the candidate window never
    /// covers the line being typed.
    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        let viewport = enclosingScrollView?.documentVisibleRect ?? bounds
        let point = NSPoint(x: viewport.minX, y: viewport.maxY)
        let inWindow = convert(NSRect(origin: point, size: .zero), to: nil)
        return window?.convertToScreen(inWindow) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }

    // MARK: - Mouse and scroll

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectionAnchor = gridPoint(for: event)
        selectionHead = selectionAnchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionAnchor != nil else { return }
        selectionHead = gridPoint(for: event)
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // A click with no drag clears the selection rather than leaving a
        // zero-width one behind, matching a terminal.
        if selectionAnchor == selectionHead {
            selectionAnchor = nil
            selectionHead = nil
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // An alternate-screen pane has no scrollback to mirror: the host
        // scrolls its own view instead, so the TUI (an agent's history
        // view, a pager) sees the wheel.
        guard isAltScreen, isInputEnabled else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / lineHeight
            : event.scrollingDeltaY
        let total = scrollRemainder + delta
        let whole = total.rounded(.towardZero)
        scrollRemainder = total - whole
        guard whole != 0 else { return }
        onSendScroll?(Double(whole))
    }

    private func gridPoint(for event: NSEvent) -> GridPoint {
        let point = convert(event.locationInWindow, from: nil)
        let row = min(
            max(0, Int(point.y / lineHeight)),
            max(0, lines.count - 1)
        )
        let column = max(0, Int((point.x / cellWidth).rounded()))
        return GridPoint(row: row, column: column)
    }

    private func normalizedSelection() -> (start: GridPoint, end: GridPoint)? {
        guard let anchor = selectionAnchor, let head = selectionHead,
              anchor != head
        else { return nil }
        return anchor < head ? (anchor, head) : (head, anchor)
    }

    private func clampSelection() {
        guard let anchor = selectionAnchor, let head = selectionHead else {
            return
        }
        let lastRow = max(0, lines.count - 1)
        if anchor.row > lastRow || head.row > lastRow {
            selectionAnchor = nil
            selectionHead = nil
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard event.type == .rightMouseDown else { return nil }
        return makeContextMenu(
            selectionText: selectedText(),
            location: convert(event.locationInWindow, from: nil)
        )
    }

    private func makeContextMenu(
        selectionText: String?,
        location: NSPoint
    ) -> NSMenu {
        contextMenuLocation = location
        let menu = NSMenu()
        menu.autoenablesItems = false
        let moveTargets = contextMenuMoveTargets?() ?? []
        for action in GhosttySurfaceView.contextMenuActions(
            selectionText: selectionText,
            hasMoveTargets: !moveTargets.isEmpty,
            includesAddBookmark: false
        ) {
            switch action {
            case .lookUp:
                guard let selectionText else { continue }
                let preview = GhosttySurfaceView.contextMenuSelectionPreview(
                    selectionText
                )
                let item = contextMenuItem(
                    title: String(
                        format: contextMenuLabels.lookUpSelectionFormat,
                        locale: Locale.current,
                        preview
                    ),
                    action: #selector(lookUpSelectionFromMenu(_:))
                )
                item.representedObject = selectionText
                menu.addItem(item)
            case .searchWeb:
                guard let selectionText else { continue }
                let item = contextMenuItem(
                    title: contextMenuLabels.searchWithGoogle,
                    action: #selector(searchSelectionFromMenu(_:))
                )
                item.representedObject = selectionText
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            case .copy:
                menu.addItem(contextMenuItem(
                    title: contextMenuLabels.copy,
                    action: #selector(copy(_:)),
                    isEnabled: selectionText != nil
                ))
            case .paste:
                menu.addItem(contextMenuItem(
                    title: contextMenuLabels.paste,
                    action: #selector(paste(_:)),
                    isEnabled: isInputEnabled
                        && NSPasteboard.general.string(forType: .string) != nil
                ))
            case .addBookmark:
                // A remote pane mirrors another Mac's terminal: it has no
                // local scrollback to pin a bookmark against, so this
                // action (shared with GhosttySurfaceView's context menu)
                // is intentionally not offered here.
                continue
            case .selectAll:
                menu.addItem(contextMenuItem(
                    title: contextMenuLabels.selectAll,
                    action: #selector(selectAll(_:))
                ))
            case .share:
                guard let selectionText else { continue }
                let picker = NSSharingServicePicker(
                    items: [selectionText as NSString]
                )
                contextMenuSharingPicker = picker
                let item = picker.standardShareMenuItem
                item.title = contextMenuLabels.share
                menu.addItem(item)
            case .services:
                let servicesMenu = NSMenu(title: contextMenuLabels.services)
                let item = NSMenuItem(
                    title: contextMenuLabels.services,
                    action: nil,
                    keyEquivalent: ""
                )
                item.submenu = servicesMenu
                item.isEnabled = true
                NSApplication.shared.registerServicesMenuSendTypes(
                    [.string],
                    returnTypes: []
                )
                NSApplication.shared.servicesMenu = servicesMenu
                menu.addItem(item)
            case .moveToTab:
                let item = NSMenuItem(
                    title: contextMenuLabels.moveToTab,
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = true
                let submenu = NSMenu(title: contextMenuLabels.moveToTab)
                submenu.autoenablesItems = false
                for target in moveTargets {
                    let targetItem = contextMenuItem(
                        title: target.title,
                        action: #selector(movePaneToTabFromMenu(_:))
                    )
                    targetItem.representedObject = target.id
                    submenu.addItem(targetItem)
                }
                item.submenu = submenu
                menu.addItem(item)
            case .closePane:
                menu.addItem(contextMenuItem(
                    title: contextMenuLabels.closePane,
                    action: #selector(closePaneFromMenu(_:))
                ))
            }
        }
        return menu
    }

    private func contextMenuItem(
        title: String,
        action: Selector,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    @objc private func lookUpSelectionFromMenu(_ sender: NSMenuItem) {
        guard let selectionText = sender.representedObject as? String else {
            return
        }
        showDefinition(
            for: NSAttributedString(string: selectionText),
            at: contextMenuLocation
        )
    }

    @objc private func searchSelectionFromMenu(_ sender: NSMenuItem) {
        guard let selectionText = sender.representedObject as? String,
              let url = GhosttySurfaceView.contextMenuSearchURL(
                  for: selectionText
              )
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func movePaneToTabFromMenu(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? UUID else {
            return
        }
        onMovePane?(destination)
    }

    @objc private func closePaneFromMenu(_ sender: Any?) {
        onClosePane?()
    }

    /// A clipboard paste routed through the standard responder chain, so
    /// the context menu's Paste item, the Edit menu, and Cmd+V all reach
    /// the same place.
    @objc func paste(_ sender: Any?) {
        guard isInputEnabled else { return }
        onPaste?()
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if sendType == .string, returnType == nil, selectedText() != nil {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc(writeSelectionToPasteboard:types:)
    func writeSelection(
        to pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        guard types.contains(.string), let text = selectedText() else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    // MARK: - Copy

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(copy(_:)) {
            return normalizedSelection() != nil
        }
        return super.responds(to: selector)
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedText(), !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Selects the whole mirrored buffer, so Select All then Copy lifts the
    /// pane's scrollback the way it would in a local terminal.
    @objc override func selectAll(_ sender: Any?) {
        guard !plainLines.isEmpty else { return }
        selectionAnchor = GridPoint(row: 0, column: 0)
        selectionHead = GridPoint(
            row: plainLines.count - 1,
            column: RemoteCellWidth.displayWidth(plainLines[plainLines.count - 1])
        )
        needsDisplay = true
    }

    private func selectedText() -> String? {
        guard let selection = normalizedSelection() else { return nil }
        var result: [String] = []
        for row in selection.start.row...selection.end.row {
            guard row < plainLines.count else { break }
            let line = plainLines[row]
            let start = row == selection.start.row ? selection.start.column : 0
            let end = row == selection.end.row
                ? selection.end.column
                : RemoteCellWidth.displayWidth(line)
            result.append(Self.slice(line, fromCell: start, toCell: end))
        }
        return result.joined(separator: "\n")
    }

    /// Cuts a line between two cell columns. Cells are not characters — one
    /// CJK character spans two — so this walks the line accumulating widths
    /// instead of slicing by character offset.
    private static func slice(
        _ line: String,
        fromCell start: Int,
        toCell end: Int
    ) -> String {
        guard end > start else { return "" }
        var result = ""
        var cell = 0
        for character in line {
            let width = RemoteCellWidth.displayWidth(of: character)
            if cell >= end { break }
            if cell >= start { result.append(character) }
            cell += width
        }
        return result
    }
}
