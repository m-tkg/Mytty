import AppKit
import Darwin
import GhosttyKit

public enum GhosttySurfaceEvent: Equatable, Sendable {
    case titleChanged(String)
    case workingDirectoryChanged(URL)
    case cellSizeChanged(CGSize)
    case rendererHealthChanged(Bool)
    case commandFinished(exitCode: Int?, durationNanoseconds: UInt64)
    case childExited(code: UInt32, runtimeMilliseconds: UInt64)
    case closeRequested(processAlive: Bool)
    /// The user asked to close this pane from its context menu. Unlike
    /// `closeRequested`, this is an explicit command that must close a
    /// pane whose process is still alive (after the app's confirmation).
    case closePaneRequested
    /// The user chose "Move to Tab" from the context menu, picking one
    /// of the window's other tabs as the destination.
    case movePaneRequested(destinationTab: UUID)
    case newTabRequested
    case closeTabRequested
    case newWindowRequested
    case closeWindowRequested
    case openURLRequested(URL)
    case focusChanged(Bool)
}

public enum GhosttySurfaceError: Error, Equatable, Sendable {
    case creationFailed
}

public struct GhosttyGridSize: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

public struct GhosttyGridPosition: Equatable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public struct GhosttySearchLabels: Equatable, Sendable {
    public var placeholder: String
    public var previousMatch: String
    public var nextMatch: String
    public var closeSearch: String

    public init(
        placeholder: String = "Find",
        previousMatch: String = "Previous match",
        nextMatch: String = "Next match",
        closeSearch: String = "Close search"
    ) {
        self.placeholder = placeholder
        self.previousMatch = previousMatch
        self.nextMatch = nextMatch
        self.closeSearch = closeSearch
    }
}

public struct GhosttyContextMenuLabels: Equatable, Sendable {
    public var copy: String
    public var paste: String
    public var selectAll: String
    public var lookUpSelectionFormat: String
    public var searchWithGoogle: String
    public var share: String
    public var services: String
    public var moveToTab: String
    public var closePane: String

    public init(
        copy: String = "Copy",
        paste: String = "Paste",
        selectAll: String = "Select All",
        lookUpSelectionFormat: String = "Look Up “%@”",
        searchWithGoogle: String = "Search with Google",
        share: String = "Share",
        services: String = "Services",
        moveToTab: String = "Move to Tab",
        closePane: String = "Close Pane"
    ) {
        self.copy = copy
        self.paste = paste
        self.selectAll = selectAll
        self.lookUpSelectionFormat = lookUpSelectionFormat
        self.searchWithGoogle = searchWithGoogle
        self.share = share
        self.services = services
        self.moveToTab = moveToTab
        self.closePane = closePane
    }
}

/// A tab a pane can be moved into from the context menu's "Move to Tab"
/// submenu.
public struct GhosttyContextMenuMoveTarget: Equatable, Sendable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

enum GhosttyContextMenuAction: Equatable, Sendable {
    case lookUp
    case searchWeb
    case separator
    case copy
    case paste
    case selectAll
    case share
    case services
    case moveToTab
    case closePane
}

enum GhosttyTextCommitDelivery: Equatable, Sendable {
    case accumulator
    case committedPreedit
    case directText
}

struct GhosttyTextCommitPlan: Equatable, Sendable {
    let clearsMarkedText: Bool
    let delivery: GhosttyTextCommitDelivery
}

@MainActor
public final class GhosttySurfaceView: NSView, @preconcurrency NSTextInputClient {
    public var onEvent: ((GhosttySurfaceEvent) -> Void)?
    public var onKeyIntercept: ((NSEvent) -> Bool)?
    /// Supplies the "Move to Tab" submenu contents on demand; empty (or
    /// nil) hides the submenu entirely.
    public var contextMenuMoveTargets: (() -> [GhosttyContextMenuMoveTarget])?

    public private(set) var terminalTitle = ""
    public private(set) var workingDirectory: URL?
    public private(set) var cellSize = CGSize(width: 8, height: 16)
    public private(set) var rendererIsHealthy = true
    public private(set) var isTerminalFocused = true
    public private(set) var autocompleteSuggestionText: String?
    public private(set) var isSearchPresented = false

    private let runtime: GhosttyRuntime
    private var contextMenuLabels: GhosttyContextMenuLabels
    private var native: ghostty_surface_t?
    private var markedText = NSMutableAttributedString()
    private var markedSelection = NSRange(location: 0, length: 0)
    private var keyTextAccumulator: [String]?
    private var trackingArea: NSTrackingArea?
    private var contextMenuLocation = NSPoint.zero
    private var contextMenuSharingPicker: NSSharingServicePicker?
    private let searchBar: GhosttySearchBarView
    private var searchUpdateTask: Task<Void, Never>?
    private lazy var autocompleteSuggestionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.isEnabled = false
        label.isHidden = true
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.textColor = .tertiaryLabelColor
        return label
    }()

    public override var acceptsFirstResponder: Bool { true }

    public var needsConfirmQuit: Bool {
        guard let native else { return false }
        return ghostty_surface_needs_confirm_quit(native)
    }

    public var foregroundProcessID: pid_t {
        guard let native else { return 0 }
        let value = ghostty_surface_foreground_pid(native)
        guard value <= UInt64(Int32.max) else { return 0 }
        return pid_t(value)
    }

    public func refresh() {
        guard let native else { return }
        ghostty_surface_refresh(native)
    }

    public func drawImmediately() {
        guard let native else { return }
        ghostty_surface_draw(native)
    }

    public func setFocused(_ focused: Bool) {
        guard isTerminalFocused != focused else { return }
        isTerminalFocused = focused
        guard let native else { return }
        ghostty_surface_set_focus(native, focused)
    }

    public init(
        runtime: GhosttyRuntime,
        workingDirectory: URL? = nil,
        initialInput: String? = nil,
        restoredTerminalHistory: String? = nil,
        environmentVariables: [String: String] = [:],
        initialSize: NSSize? = nil,
        searchLabels: GhosttySearchLabels = GhosttySearchLabels(),
        contextMenuLabels: GhosttyContextMenuLabels
            = GhosttyContextMenuLabels()
    ) throws {
        self.runtime = runtime
        self.workingDirectory = workingDirectory
        self.native = nil
        self.searchBar = GhosttySearchBarView(labels: searchLabels)
        self.contextMenuLabels = contextMenuLabels

        super.init(
            frame: NSRect(
                origin: .zero,
                size: initialSize ?? NSSize(width: 800, height: 600)
            )
        )

        guard let app = runtime.nativeApp else {
            throw GhosttySurfaceError.creationFailed
        }

        var configuration = ghostty_surface_config_new()
        configuration.platform_tag = GHOSTTY_PLATFORM_MACOS
        configuration.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        configuration.userdata = Unmanaged.passUnretained(self).toOpaque()
        configuration.scale_factor = Double(
            NSScreen.main?.backingScaleFactor ?? 1
        )
        configuration.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        var environmentStorage = try makeEnvironmentStorage(
            environmentVariables
        )
        defer {
            releaseEnvironmentStorage(environmentStorage)
        }
        let surface = environmentStorage.withUnsafeMutableBufferPointer {
            environment in
            configuration.env_vars = environment.baseAddress
            configuration.env_var_count = environment.count
            return withOptionalCString(workingDirectory?.path) { path in
                configuration.working_directory = path
                return withOptionalCString(initialInput) { input in
                    configuration.initial_input = input
                    return ghostty_surface_new(app, &configuration)
                }
            }
        }

        guard let surface else {
            throw GhosttySurfaceError.creationFailed
        }
        native = surface

        if let restoredTerminalHistory, !restoredTerminalHistory.isEmpty {
            // End the replay on a fresh line: the capture stops mid-line at
            // the old prompt, and a shell starting with the cursor mid-line
            // emits its partial-line mark (zsh's inverse "%" plus a row of
            // spaces), which re-wraps into artifacts on every restore.
            let replay = restoredTerminalHistory.hasSuffix("\n")
                ? restoredTerminalHistory
                : restoredTerminalHistory + "\r\n"
            _ = replay.withCString { pointer in
                ghostty_surface_write_text(
                    surface,
                    pointer,
                    replay.lengthOfBytes(using: .utf8)
                )
            }
        }

        addSubview(autocompleteSuggestionLabel)
        configureSearchBar()
        updateTrackingAreas()
        updateSurfaceGeometry()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeEnvironmentStorage(
        _ environment: [String: String]
    ) throws -> [ghostty_env_var_s] {
        var result: [ghostty_env_var_s] = []
        result.reserveCapacity(environment.count)

        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            guard let keyPointer = strdup(key) else {
                releaseEnvironmentStorage(result)
                throw GhosttySurfaceError.creationFailed
            }
            guard let valuePointer = strdup(value) else {
                free(keyPointer)
                releaseEnvironmentStorage(result)
                throw GhosttySurfaceError.creationFailed
            }
            result.append(
                ghostty_env_var_s(
                    key: keyPointer,
                    value: valuePointer
                )
            )
        }
        return result
    }

    private func releaseEnvironmentStorage(
        _ environment: [ghostty_env_var_s]
    ) {
        for entry in environment {
            free(UnsafeMutablePointer(mutating: entry.key))
            free(UnsafeMutablePointer(mutating: entry.value))
        }
    }

    isolated deinit {
        searchUpdateTask?.cancel()
        if let native {
            ghostty_surface_free(native)
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            setFocused(true)
            onEvent?(.focusChanged(true))
        }
        return accepted
    }

    public override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            setFocused(false)
            onEvent?(.focusChanged(false))
        }
        return accepted
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSurfaceGeometry()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceGeometry()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceGeometry()
        positionAutocompleteSuggestion()
    }

    nonisolated static func shouldDrawImmediatelyAfterResize(
        isFocused: Bool
    ) -> Bool {
        !isFocused
    }

    public override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    private func updateSurfaceGeometry() {
        guard let native else { return }
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        ghostty_surface_set_content_scale(native, scale, scale)

        let backingSize = convertToBacking(bounds).size
        guard bounds.width >= cellSize.width,
              bounds.height >= cellSize.height
        else { return }
        ghostty_surface_set_size(
            native,
            UInt32(backingSize.width.rounded()),
            UInt32(backingSize.height.rounded())
        )
        if Self.shouldDrawImmediatelyAfterResize(
            isFocused: isTerminalFocused
        ) {
            ghostty_surface_draw(native)
        }
    }

    var terminalBackingSize: CGSize {
        guard let native else { return .zero }
        let size = ghostty_surface_size(native)
        return CGSize(
            width: Int(size.width_px),
            height: Int(size.height_px)
        )
    }

    public var terminalGridSize: GhosttyGridSize {
        guard let native else {
            return GhosttyGridSize(columns: 0, rows: 0)
        }
        let size = ghostty_surface_size(native)
        return GhosttyGridSize(
            columns: Int(size.columns),
            rows: Int(size.rows)
        )
    }

    func receiveTitle(_ title: String) {
        terminalTitle = title
        onEvent?(.titleChanged(title))
    }

    func receiveWorkingDirectory(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        workingDirectory = url
        onEvent?(.workingDirectoryChanged(url))
    }

    func receiveCellSize(width: UInt32, height: UInt32) {
        let backing = CGSize(width: Int(width), height: Int(height))
        cellSize = convertFromBacking(backing)
        positionAutocompleteSuggestion()
        onEvent?(.cellSizeChanged(cellSize))
    }

    func receiveRendererHealth(_ healthy: Bool) {
        rendererIsHealthy = healthy
        onEvent?(.rendererHealthChanged(healthy))
    }

    func receiveCommandFinished(
        exitCode: Int?,
        durationNanoseconds: UInt64
    ) {
        onEvent?(
            .commandFinished(
                exitCode: exitCode,
                durationNanoseconds: durationNanoseconds
            )
        )
    }

    func receiveChildExit(code: UInt32, runtimeMilliseconds: UInt64) {
        onEvent?(
            .childExited(
                code: code,
                runtimeMilliseconds: runtimeMilliseconds
            )
        )
    }

    func receiveCloseRequest(processAlive: Bool) {
        onEvent?(.closeRequested(processAlive: processAlive))
    }

    func receiveNewTabRequest() {
        onEvent?(.newTabRequested)
    }

    func receiveCloseTabRequest() {
        onEvent?(.closeTabRequested)
    }

    func receiveNewWindowRequest() {
        onEvent?(.newWindowRequested)
    }

    func receiveCloseWindowRequest() {
        onEvent?(.closeWindowRequested)
    }

    func receiveOpenURLRequest(_ url: URL) {
        onEvent?(.openURLRequested(url))
    }

    func receiveStartSearch(_ needle: String?) {
        if let needle, !needle.isEmpty {
            searchBar.query = needle
        }
        isSearchPresented = true
        searchBar.isHidden = false
        if !searchBar.query.isEmpty {
            updateSearchQuery(searchBar.query)
        }
        searchBar.focusField()
    }

    func receiveEndSearch() {
        dismissSearchBar()
    }

    func receiveSearchTotal(_ total: Int?) {
        guard isSearchPresented else { return }
        searchBar.total = total
    }

    func receiveSearchSelected(_ selected: Int?) {
        guard isSearchPresented else { return }
        searchBar.selected = selected
    }

    public func showSearch() {
        if isSearchPresented {
            searchBar.focusField()
            return
        }
        guard performBindingAction("start_search") else { return }
        receiveStartSearch(nil)
    }

    public func closeSearch() {
        guard isSearchPresented else { return }
        dismissSearchBar()
        _ = performBindingAction("end_search")
        window?.makeFirstResponder(self)
    }

    public func updateSearchLabels(_ labels: GhosttySearchLabels) {
        searchBar.update(labels: labels)
    }

    private func configureSearchBar() {
        searchBar.isHidden = true
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.onQueryChanged = { [weak self] query in
            self?.updateSearchQuery(query)
        }
        searchBar.onFocus = { [weak self] in
            guard let self else { return }
            self.setFocused(true)
            self.onEvent?(.focusChanged(true))
        }
        searchBar.onPrevious = { [weak self] in
            _ = self?.performBindingAction("navigate_search:previous")
        }
        searchBar.onNext = { [weak self] in
            _ = self?.performBindingAction("navigate_search:next")
        }
        searchBar.onClose = { [weak self] in
            self?.closeSearch()
        }
        addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            searchBar.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 8
            ),
            searchBar.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }

    private func dismissSearchBar() {
        searchUpdateTask?.cancel()
        searchUpdateTask = nil
        isSearchPresented = false
        searchBar.isHidden = true
        searchBar.total = nil
        searchBar.selected = nil
    }

    private func updateSearchQuery(_ query: String) {
        searchUpdateTask?.cancel()
        searchUpdateTask = nil
        searchBar.total = nil
        searchBar.selected = nil
        if query.isEmpty || query.count >= 3 {
            _ = performBindingAction("search:\(query)")
            return
        }
        searchUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            _ = self?.performBindingAction("search:\(query)")
        }
    }

    @discardableResult
    private func performBindingAction(_ action: String) -> Bool {
        guard let native else { return false }
        return action.withCString { pointer in
            ghostty_surface_binding_action(
                native,
                pointer,
                UInt(action.lengthOfBytes(using: .utf8))
            )
        }
    }

    public func visibleText() -> String {
        readText(tag: GHOSTTY_POINT_VIEWPORT)
    }

    /// The entire screen buffer including scrollback, not just the
    /// visible viewport.
    public func screenText() -> String {
        readText(tag: GHOSTTY_POINT_SCREEN)
    }

    /// The entire screen buffer encoded as replayable VT/ANSI output.
    public func screenVTText() -> String {
        readText(tag: GHOSTTY_POINT_SCREEN, preservesAttributes: true)
    }

    private func readText(
        tag: ghostty_point_tag_e,
        preservesAttributes: Bool = false
    ) -> String {
        guard let native else { return "" }
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: tag,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: tag,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )
        var text = ghostty_text_s()
        let didRead = preservesAttributes
            ? ghostty_surface_read_text_vt(native, selection, &text)
            : ghostty_surface_read_text(native, selection, &text)
        guard didRead,
              let pointer = text.text
        else { return "" }
        defer { ghostty_surface_free_text(native, &text) }

        let bytes = UnsafeRawPointer(pointer)
            .assumingMemoryBound(to: UInt8.self)
        return String(
            decoding: UnsafeBufferPointer(
                start: bytes,
                count: Int(text.text_len)
            ),
            as: UTF8.self
        )
    }

    public override func keyDown(with event: NSEvent) {
        guard native != nil else { return }

        let markedBefore = hasMarkedText()
        keyTextAccumulator = []
        interpretKeyEvents([event])
        let accumulated = keyTextAccumulator ?? []
        keyTextAccumulator = nil

        syncPreedit(clearIfNeeded: markedBefore)

        let action = event.isARepeat
            ? GHOSTTY_ACTION_REPEAT
            : GHOSTTY_ACTION_PRESS
        let composing = hasMarkedText() || markedBefore
        if onKeyIntercept?(event) == true {
            return
        }

        if markedBefore, !accumulated.isEmpty {
            for text in accumulated where !Self.shouldSuppressComposingControlInput(
                text,
                composing: composing
            ) {
                _ = sendCommittedPreedit(text, action: action)
            }
            return
        }

        if accumulated.isEmpty {
            if Self.shouldSuppressComposingControlInput(
                event.characters,
                composing: composing
            ) {
                return
            }
            _ = sendKey(
                event,
                action: action,
                text: event.ghosttyText,
                composing: composing
            )
        } else {
            for text in accumulated where !Self.shouldSuppressComposingControlInput(
                text,
                composing: composing
            ) {
                _ = sendKey(event, action: action, text: text)
            }
        }
    }

    public override func keyUp(with event: NSEvent) {
        _ = sendKey(event, action: GHOSTTY_ACTION_RELEASE)
    }

    public override func flagsChanged(with event: NSEvent) {
        let active = event.modifierFlags.intersection(
            [.shift, .control, .option, .command, .capsLock]
        ).isEmpty == false
        _ = sendKey(
            event,
            action: active ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        )
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              !event.modifierFlags.intersection([.command, .control]).isEmpty
        else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command),
           NSApplication.shared.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        guard window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }

    private func sendKey(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let native else { return false }
        var input = event.ghosttyInput(action: action)
        input.composing = composing

        guard let text, !text.isEmpty,
              text.utf8.first.map({ $0 >= 0x20 }) == true
        else {
            return ghostty_surface_key(native, input)
        }

        return text.withCString { pointer in
            input.text = pointer
            return ghostty_surface_key(native, input)
        }
    }

    private func sendCommittedPreedit(
        _ text: String,
        action: ghostty_input_action_e
    ) -> Bool {
        guard let native else { return false }
        var input = ghostty_input_key_s()
        input.action = action
        input.mods = GHOSTTY_MODS_NONE
        input.consumed_mods = GHOSTTY_MODS_NONE

        return text.withCString { pointer in
            input.text = pointer
            return ghostty_surface_key(native, input)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    public override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    public override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard event.type == .rightMouseDown else { return nil }
        return makeContextMenu(
            selectionText: terminalSelectionText,
            location: convert(event.locationInWindow, from: nil)
        )
    }

    func makeContextMenu(
        selectionText: String?,
        location: NSPoint
    ) -> NSMenu {
        contextMenuLocation = location
        let menu = NSMenu()
        menu.autoenablesItems = false
        let moveTargets = contextMenuMoveTargets?() ?? []
        for action in Self.contextMenuActions(
            selectionText: selectionText,
            hasMoveTargets: !moveTargets.isEmpty
        ) {
            switch action {
            case .lookUp:
                guard let selectionText else { continue }
                let preview = Self.contextMenuSelectionPreview(selectionText)
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
                    action: #selector(copySelectionFromMenu(_:)),
                    isEnabled: selectionText != nil
                ))
            case .paste:
                menu.addItem(contextMenuItem(
                    title: contextMenuLabels.paste,
                    action: #selector(pasteFromMenu(_:)),
                    isEnabled: NSPasteboard.general.string(
                        forType: .string
                    ) != nil
                ))
            case .selectAll:
                menu.addItem(contextMenuItem(
                    title: contextMenuLabels.selectAll,
                    action: #selector(selectAllFromMenu(_:))
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

    @objc private func closePaneFromMenu(_ sender: Any?) {
        onEvent?(.closePaneRequested)
    }

    @objc private func movePaneToTabFromMenu(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? UUID else {
            return
        }
        onEvent?(.movePaneRequested(destinationTab: destination))
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

    private var terminalSelectionText: String? {
        guard let native else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(native, &text) else {
            return nil
        }
        defer { ghostty_surface_free_text(native, &text) }
        guard text.text_len > 0, let pointer = text.text else { return nil }
        let bytes = UnsafeRawPointer(pointer)
            .assumingMemoryBound(to: UInt8.self)
        return String(
            decoding: UnsafeBufferPointer(
                start: bytes,
                count: Int(text.text_len)
            ),
            as: UTF8.self
        )
    }

    nonisolated static func contextMenuActions(
        selectionText: String?,
        hasMoveTargets: Bool
    ) -> [GhosttyContextMenuAction] {
        let trailing: [GhosttyContextMenuAction] =
            (hasMoveTargets ? [.moveToTab] : []) + [.closePane]

        guard let selectionText, !selectionText.isEmpty else {
            return [.paste, .separator, .selectAll, .separator] + trailing
        }
        guard !selectionText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return [
                .copy, .paste, .separator, .selectAll, .separator,
            ] + trailing
        }
        return [
            .lookUp,
            .searchWeb,
            .separator,
            .copy,
            .paste,
            .separator,
            .selectAll,
            .separator,
            .share,
            .services,
            .separator,
        ] + trailing
    }

    nonisolated static func contextMenuSelectionPreview(
        _ selectionText: String
    ) -> String {
        let collapsed = selectionText
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let maximumLength = 40
        guard collapsed.count > maximumLength else { return collapsed }
        return String(collapsed.prefix(maximumLength - 1)) + "…"
    }

    nonisolated static func contextMenuSearchURL(
        for selectionText: String
    ) -> URL? {
        var components = URLComponents(
            string: "https://www.google.com/search"
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: selectionText),
        ]
        return components?.url
    }

    public func updateContextMenuLabels(_ labels: GhosttyContextMenuLabels) {
        contextMenuLabels = labels
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
              let url = Self.contextMenuSearchURL(for: selectionText)
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copySelectionFromMenu(_ sender: Any?) {
        _ = performBindingAction("copy_to_clipboard")
    }

    @objc private func pasteFromMenu(_ sender: Any?) {
        _ = performBindingAction("paste_from_clipboard")
    }

    @objc private func selectAllFromMenu(_ sender: Any?) {
        _ = performBindingAction("select_all")
    }

    public override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if sendType == .string,
           returnType == nil,
           terminalSelectionText != nil {
            return self
        }
        return super.validRequestor(
            forSendType: sendType,
            returnType: returnType
        )
    }

    @objc(writeSelectionToPasteboard:types:)
    public func writeSelection(
        to pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        guard types.contains(.string),
              let selectionText = terminalSelectionText
        else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(selectionText, forType: .string)
    }

    public override func rightMouseUp(with event: NSEvent) {
        super.rightMouseUp(with: event)
    }

    @discardableResult
    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) -> Bool {
        guard let native else { return false }
        return ghostty_surface_mouse_button(
            native,
            state,
            button,
            Self.mouseEventMods(
                event.modifierFlags.ghosttyMods,
                mouseCaptured: ghostty_surface_mouse_captured(native)
            )
        )
    }

    public override func mouseMoved(with event: NSEvent) {
        guard let native else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            native,
            point.x,
            bounds.height - point.y,
            Self.mouseEventMods(
                event.modifierFlags.ghosttyMods,
                mouseCaptured: ghostty_surface_mouse_captured(native)
            )
        )
    }

    /// Ghostty only evaluates link hover/clicks while a TUI captures the
    /// mouse if shift is held (its capture-bypass modifier), so ⌘ alone
    /// never reaches the link path in agent TUIs like Claude Code. Treat ⌘
    /// as the same bypass by adding shift before handing mods to Ghostty.
    nonisolated static func mouseEventMods(
        _ mods: ghostty_input_mods_e,
        mouseCaptured: Bool
    ) -> ghostty_input_mods_e {
        guard mouseCaptured,
              mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0,
              mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue == 0
        else { return mods }
        return ghostty_input_mods_e(
            mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue
        )
    }

    public override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let native else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }
        let precision = event.hasPreciseScrollingDeltas ? 1 : 0
        let momentum = event.momentumPhase.ghosttyMomentum
        let modifiers = Int32(precision | (momentum << 1))
        ghostty_surface_mouse_scroll(native, x, y, modifiers)
    }

    public func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    public func markedRange() -> NSRange {
        guard hasMarkedText() else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.length)
    }

    public func selectedRange() -> NSRange {
        guard let native else {
            return NSRange(location: NSNotFound, length: 0)
        }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(native, &text) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        defer { ghostty_surface_free_text(native, &text) }
        return NSRange(
            location: Int(text.offset_start),
            length: Int(text.offset_len)
        )
    }

    public func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        switch string {
        case let value as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: value)
        case let value as String:
            markedText = NSMutableAttributedString(string: value)
        default:
            return
        }
        markedSelection = selectedRange
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    public func unmarkText() {
        guard hasMarkedText() else { return }
        markedText.mutableString.setString("")
        markedSelection = NSRange(location: 0, length: 0)
        syncPreedit()
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    public func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        nil
    }

    public func characterIndex(for point: NSPoint) -> Int {
        0
    }

    public func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        let rect = terminalCursorRect
        guard rect != .zero else { return .zero }
        guard let window else { return convert(rect, to: nil) }
        return window.convertToScreen(convert(rect, to: nil))
    }

    public func setAutocompleteSuggestion(_ text: String?) {
        let suggestion = text.flatMap { $0.isEmpty ? nil : $0 }
        autocompleteSuggestionText = suggestion
        autocompleteSuggestionLabel.stringValue = suggestion ?? ""
        autocompleteSuggestionLabel.isHidden = suggestion == nil
        positionAutocompleteSuggestion()
    }

    public var terminalCursorRect: NSRect {
        guard let native else { return .zero }
        var x = 0.0
        var y = 0.0
        var width = Double(cellSize.width)
        var height = Double(cellSize.height)
        ghostty_surface_ime_point(native, &x, &y, &width, &height)

        return NSRect(
            x: CGFloat(x),
            y: bounds.height - CGFloat(y),
            width: CGFloat(width),
            height: max(CGFloat(height), cellSize.height)
        )
    }

    /// The cursor's grid coordinates (zero-based, from the viewport's
    /// top-left), derived from the IME caret point and the cell size.
    public var terminalCursorPosition: GhosttyGridPosition? {
        guard let native, cellSize.width > 0, cellSize.height > 0 else {
            return nil
        }
        var x = 0.0
        var y = 0.0
        var width = Double(cellSize.width)
        var height = Double(cellSize.height)
        ghostty_surface_ime_point(native, &x, &y, &width, &height)

        let grid = terminalGridSize
        guard grid.columns > 0, grid.rows > 0 else { return nil }
        // The IME point is the *bottom-right* corner of the cursor's
        // cell (where a candidate window would hang), so both indexes
        // are one less than the edge's cell multiple. Verified against a
        // live shell in the cursorGridPosition integration test.
        let column = Int((x / Double(cellSize.width)).rounded()) - 1
        let row = Int((y / Double(cellSize.height)).rounded()) - 1
        return GhosttyGridPosition(
            row: min(max(row, 0), grid.rows - 1),
            column: min(max(column, 0), grid.columns - 1)
        )
    }

    private func positionAutocompleteSuggestion() {
        guard !autocompleteSuggestionLabel.isHidden else { return }
        let cursor = terminalCursorRect
        guard cursor != .zero else { return }

        let pointSize = max(10, cellSize.height * 0.72)
        autocompleteSuggestionLabel.font = NSFont.monospacedSystemFont(
            ofSize: pointSize,
            weight: .regular
        )
        let fittingSize = autocompleteSuggestionLabel.intrinsicContentSize
        let availableWidth = max(0, bounds.width - cursor.minX)
        autocompleteSuggestionLabel.frame = NSRect(
            x: cursor.minX,
            y: cursor.minY + (cursor.height - fittingSize.height) / 2,
            width: min(fittingSize.width, availableWidth),
            height: fittingSize.height
        )
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let value: String
        switch string {
        case let attributed as NSAttributedString:
            value = attributed.string
        case let plain as String:
            value = plain
        default:
            return
        }

        let plan = Self.textCommitPlan(
            hadMarkedText: hasMarkedText(),
            isAccumulatingKeyEvent: keyTextAccumulator != nil
        )
        if plan.clearsMarkedText {
            unmarkText()
        }

        switch plan.delivery {
        case .accumulator:
            keyTextAccumulator?.append(value)
        case .committedPreedit:
            _ = sendCommittedPreedit(value, action: GHOSTTY_ACTION_PRESS)
        case .directText:
            sendText(value)
        }
    }

    public override func doCommand(by selector: Selector) {
        // Intentionally consume commands that AppKit would otherwise beep for.
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let native else { return }
        if hasMarkedText() {
            let string = markedText.string
            string.withCString { pointer in
                ghostty_surface_preedit(
                    native,
                    pointer,
                    UInt(string.lengthOfBytes(using: .utf8))
                )
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(native, nil, 0)
        }
    }

    nonisolated static func shouldSuppressComposingControlInput(
        _ text: String?,
        composing: Bool
    ) -> Bool {
        guard composing, let text else { return false }
        let scalars = text.unicodeScalars
        guard let scalar = scalars.first,
              scalars.index(after: scalars.startIndex) == scalars.endIndex
        else { return false }
        return scalar.value < 0x20
    }

    nonisolated static func textCommitPlan(
        hadMarkedText: Bool,
        isAccumulatingKeyEvent: Bool
    ) -> GhosttyTextCommitPlan {
        let delivery: GhosttyTextCommitDelivery
        if isAccumulatingKeyEvent {
            delivery = .accumulator
        } else if hadMarkedText {
            delivery = .committedPreedit
        } else {
            delivery = .directText
        }
        return GhosttyTextCommitPlan(
            clearsMarkedText: true,
            delivery: delivery
        )
    }

    /// Injects a synthetic mouse-wheel scroll (positive deltaY = toward
    /// older content), used by the iOS remote to scroll alternate-screen
    /// TUIs that have no scrollback to mirror.
    public func sendScroll(deltaY: Double) {
        guard let native else { return }
        // Wheel events sent as mouse reports carry ghostty's cached
        // pointer position, which only updates while the physical pointer
        // moves over this view — with the pointer elsewhere the report's
        // coordinates are stale and mouse-reporting TUIs ignore it. Pin
        // the position to the view's center so a remote scroll works no
        // matter where the Mac's pointer is.
        ghostty_surface_mouse_pos(
            native,
            bounds.width / 2,
            bounds.height / 2,
            NSEvent.ModifierFlags([]).ghosttyMods
        )
        ghostty_surface_mouse_scroll(native, 0, deltaY, 0)
    }

    public func sendText(_ string: String) {
        guard let native, !string.isEmpty else { return }
        string.withCString { pointer in
            ghostty_surface_text(
                native,
                pointer,
                UInt(string.lengthOfBytes(using: .utf8))
            )
        }
    }

    public func sendEnter() {
        sendKeyPress(keyCode: 36, characters: "\r")
    }

    /// Synthesizes a full press/release key event, so the keystroke goes
    /// through libghostty's key encoding (kitty keyboard protocol,
    /// modifyOtherKeys, …) exactly as if typed locally — unlike
    /// `sendText`, which injects plain text and is not a key press.
    public func sendKeyPress(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else { return }
        _ = sendKey(event, action: GHOSTTY_ACTION_PRESS)
        _ = sendKey(event, action: GHOSTTY_ACTION_RELEASE)
    }

    func readClipboard(
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let native,
              let string = pasteboard(for: location).string(forType: .string)
        else { return false }
        string.withCString { pointer in
            ghostty_surface_complete_clipboard_request(
                native,
                pointer,
                state,
                false
            )
        }
        return true
    }

    func confirmClipboardRead(
        _ string: String,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let native else { return }
        let approved = request == GHOSTTY_CLIPBOARD_REQUEST_PASTE
        let value = approved ? string : ""
        value.withCString { pointer in
            ghostty_surface_complete_clipboard_request(
                native,
                pointer,
                state,
                approved
            )
        }
    }

    func writeClipboard(
        location: ghostty_clipboard_e,
        items: [ClipboardItem]
    ) {
        guard !items.isEmpty else { return }

        let pasteboard = pasteboard(for: location)
        let types = items.map { pasteboardType(for: $0.mime) }
        pasteboard.declareTypes(types, owner: nil)
        for item in items {
            pasteboard.setString(
                item.data,
                forType: pasteboardType(for: item.mime)
            )
        }
    }

    private func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard {
        if location == GHOSTTY_CLIPBOARD_SELECTION {
            return NSPasteboard(name: .init("com.m-tkg.mytty.selection"))
        }
        return .general
    }

    private func pasteboardType(for mime: String) -> NSPasteboard.PasteboardType {
        mime == "text/plain" ? .string : .init(mime)
    }
}

private func withOptionalCString<T>(
    _ string: String?,
    _ body: (UnsafePointer<CChar>?) throws -> T
) rethrows -> T {
    guard let string else { return try body(nil) }
    return try string.withCString(body)
}
