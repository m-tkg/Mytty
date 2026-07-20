import AppKit

@MainActor
final class TerminalTitlebarView: NSVisualEffectView {
    let contentOverlay = TerminalTitlebarContentView()

    var displayedTitle: String { contentOverlay.displayedTitle }
    var titleColor: NSColor { contentOverlay.titleColor }
    var titleGroupMidX: CGFloat { contentOverlay.titleGroupMidX }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .titlebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { true }

    func update(title: String, resourceURL: URL?) {
        contentOverlay.update(title: title, resourceURL: resourceURL)
    }
}

@MainActor
final class TerminalTitlebarContentView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let titleGroup = NSStackView()

    var displayedTitle: String { titleLabel.stringValue }
    var titleColor: NSColor { titleLabel.textColor ?? .clear }
    var titleGroupMidX: CGFloat { titleGroup.frame.midX }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        titleGroup.orientation = .horizontal
        titleGroup.alignment = .centerY
        titleGroup.spacing = 6
        titleGroup.translatesAutoresizingMaskIntoConstraints = false
        titleGroup.addArrangedSubview(iconView)
        titleGroup.addArrangedSubview(titleLabel)
        addSubview(titleGroup)

        NSLayoutConstraint.activate([
            titleGroup.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleGroup.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 132
            ),
            titleGroup.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { true }

    func update(title: String, resourceURL: URL?) {
        titleLabel.stringValue = title
        iconView.image = Self.resourceIcon(for: resourceURL)
        iconView.isHidden = iconView.image == nil
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private static func resourceIcon(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        let image: NSImage?
        if url.isFileURL {
            image = NSWorkspace.shared.icon(forFile: url.path).copy()
                as? NSImage
        } else {
            image = NSImage(
                systemSymbolName: "globe",
                accessibilityDescription: nil
            )
        }
        image?.size = NSSize(width: 16, height: 16)
        return image
    }
}
