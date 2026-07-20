import AppKit

@MainActor
final class PaneHostView: NSView {
    private let dimmingView = PaneDimmingView()
    private let keyToastView = PaneKeyToastView()
    private let sizeIndicatorView = PaneSizeIndicatorView()
    private let swapClickCatcher = PaneSwapClickCatcherView()
    private var keyToastHideTask: Task<Void, Never>?
    private var keyToastCursorRect: NSRect?
    private var contentConstraints: [NSLayoutConstraint] = []
    private(set) var contentView: NSView?

    var isFocused = false {
        didSet {
            dimmingView.isHidden = isFocused
        }
    }

    /// Highlights this pane as the first pane picked while a pane-swap is
    /// pending a second click, distinct from the focus dimming above.
    var isSwapCandidate = false {
        didSet {
            guard isSwapCandidate != oldValue else { return }
            updateSwapBorder()
        }
    }

    /// Highlights this pane as the current keyboard-navigation target while
    /// picking a pane with arrow keys, distinct from — and visually lighter
    /// than — a confirmed `isSwapCandidate` pick.
    var isSwapCursor = false {
        didSet {
            guard isSwapCursor != oldValue else { return }
            updateSwapBorder()
        }
    }

    private func updateSwapBorder() {
        if isSwapCandidate {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 3
        } else if isSwapCursor {
            layer?.borderColor = NSColor.controlAccentColor
                .withAlphaComponent(0.6).cgColor
            layer?.borderWidth = 2
        } else {
            layer?.borderWidth = 0
        }
    }

    var isDimmed: Bool { !dimmingView.isHidden }
    var inactiveDimmingAlpha: CGFloat {
        dimmingView.layer?.backgroundColor?.alpha ?? 0
    }
    var focusBorderWidth: CGFloat { layer?.borderWidth ?? 0 }
    var keyToastText: String { keyToastView.stringValue }
    var isKeyToastVisible: Bool { !keyToastView.isHidden }
    var keyToastFrame: NSRect { keyToastView.frame }
    var sizeIndicatorText: String { sizeIndicatorView.stringValue }
    var isSizeIndicatorVisible: Bool { !sizeIndicatorView.isHidden }
    var isSwapClickCatcherActive: Bool { !swapClickCatcher.isHidden }

    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.wantsLayer = true
        updateInactiveDimming(0.32)
        addSubview(dimmingView)
        keyToastView.isHidden = true
        addSubview(keyToastView)
        sizeIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        sizeIndicatorView.isHidden = true
        addSubview(sizeIndicatorView)
        attachContent(content)
        swapClickCatcher.translatesAutoresizingMaskIntoConstraints = false
        swapClickCatcher.isHidden = true
        addSubview(swapClickCatcher)
        let indicatorWidth = sizeIndicatorView.widthAnchor.constraint(
            equalToConstant: 104
        )
        indicatorWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sizeIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            sizeIndicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeIndicatorView.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 6
            ),
            sizeIndicatorView.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -6
            ),
            indicatorWidth,
            sizeIndicatorView.heightAnchor.constraint(equalToConstant: 34),
            swapClickCatcher.leadingAnchor.constraint(equalTo: leadingAnchor),
            swapClickCatcher.trailingAnchor.constraint(equalTo: trailingAnchor),
            swapClickCatcher.topAnchor.constraint(equalTo: topAnchor),
            swapClickCatcher.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Shows a transparent, click-capturing overlay above the pane's
    /// content so a pane-swap click is caught without also clicking through
    /// to the terminal/web content underneath, and without depending on
    /// each content type's own focus/click plumbing.
    func enableSwapClickCatcher(onClick: @escaping () -> Void) {
        swapClickCatcher.onClick = onClick
        swapClickCatcher.isHidden = false
    }

    func disableSwapClickCatcher() {
        swapClickCatcher.isHidden = true
        swapClickCatcher.onClick = nil
    }

    func updateInactiveDimming(_ amount: CGFloat) {
        let clamped = min(1, max(0, amount))
        dimmingView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(clamped)
            .cgColor
    }

    func attachContent(_ content: NSView) {
        if contentView === content, content.superview === self { return }
        detachContent()
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content, positioned: .below, relativeTo: dimmingView)
        contentView = content
        contentConstraints = [
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    override func layout() {
        super.layout()
        positionKeyToast()
    }

    func showKeyToast(
        _ text: String,
        below cursorRect: NSRect,
        duration: Duration = .milliseconds(1_200)
    ) {
        guard !text.isEmpty else { return }
        keyToastHideTask?.cancel()
        keyToastView.stringValue = text
        keyToastCursorRect = cursorRect
        positionKeyToast()
        keyToastView.isHidden = false
        keyToastHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hideKeyToast()
        }
    }

    func hideKeyToast() {
        keyToastHideTask?.cancel()
        keyToastHideTask = nil
        keyToastCursorRect = nil
        keyToastView.isHidden = true
    }

    private func positionKeyToast() {
        guard let keyToastCursorRect else { return }
        let size = keyToastView.fittingSize(
            maximumWidth: max(0, bounds.width - 12)
        )
        keyToastView.frame = PressedKeyToastLayout.frame(
            cursorRect: keyToastCursorRect,
            toastSize: size,
            in: bounds
        )
    }

    @discardableResult
    func detachContent() -> NSView? {
        guard let contentView else { return nil }
        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints.removeAll()
        contentView.removeFromSuperview()
        self.contentView = nil
        return contentView
    }

    func updateSizeIndicator(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        sizeIndicatorView.stringValue = "\(columns) x \(rows)"
    }

    func setSizeIndicatorVisible(_ visible: Bool) {
        sizeIndicatorView.isHidden = !visible
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class PaneDimmingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private final class PaneSwapClickCatcherView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

@MainActor
private final class PaneKeyToastView: NSView {
    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    func fittingSize(maximumWidth: CGFloat) -> NSSize {
        PressedKeyToastLayout.toastSize(
            for: stringValue,
            maximumWidth: maximumWidth
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PressedKeyToastLayout.cornerRadius
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.78)
            .cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white
            .withAlphaComponent(0.14)
            .cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = PressedKeyToastLayout.font()
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private final class PaneSizeIndicatorView: NSView {
    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(
            ofSize: 16,
            weight: .semibold
        )
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.92)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.textColor = .labelColor
    }
}
