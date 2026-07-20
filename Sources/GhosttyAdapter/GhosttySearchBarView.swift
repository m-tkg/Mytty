import AppKit

@MainActor
final class GhosttySearchBarView: NSVisualEffectView,
    NSSearchFieldDelegate {
    var onFocus: (() -> Void)?
    var onQueryChanged: ((String) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?

    var query: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    var total: Int? {
        didSet { updateResultLabel() }
    }

    var selected: Int? {
        didSet { updateResultLabel() }
    }

    private let searchField = NSSearchField()
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton: NSButton
    private let nextButton: NSButton
    private let closeButton: NSButton

    init(labels: GhosttySearchLabels) {
        previousButton = Self.makeButton(
            symbol: "chevron.up",
            label: labels.previousMatch
        )
        nextButton = Self.makeButton(
            symbol: "chevron.down",
            label: labels.nextMatch
        )
        closeButton = Self.makeButton(
            symbol: "xmark",
            label: labels.closeSearch
        )
        super.init(frame: .zero)

        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        searchField.placeholderString = labels.placeholder
        searchField.delegate = self
        searchField.controlSize = .small
        searchField.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        resultLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.alignment = .right
        resultLabel.setContentHuggingPriority(.required, for: .horizontal)

        previousButton.target = self
        previousButton.action = #selector(selectPrevious(_:))
        nextButton.target = self
        nextButton.action = #selector(selectNext(_:))
        closeButton.target = self
        closeButton.action = #selector(close(_:))

        let stack = NSStackView(
            views: [
                searchField,
                resultLabel,
                previousButton,
                nextButton,
                closeButton,
            ]
        )
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            searchField.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 50
            ),
        ])
        let preferredFieldWidth = searchField.widthAnchor.constraint(
            equalToConstant: 180
        )
        preferredFieldWidth.priority = .defaultHigh
        preferredFieldWidth.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(labels: GhosttySearchLabels) {
        searchField.placeholderString = labels.placeholder
        Self.updateButton(previousButton, label: labels.previousMatch)
        Self.updateButton(nextButton, label: labels.nextMatch)
        Self.updateButton(closeButton, label: labels.closeSearch)
    }

    func focusField() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        onFocus?()
    }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChanged?(searchField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApplication.shared.currentEvent?.modifierFlags.contains(.shift)
                == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    @objc private func selectPrevious(_ sender: Any?) {
        onFocus?()
        onPrevious?()
    }

    @objc private func selectNext(_ sender: Any?) {
        onFocus?()
        onNext?()
    }

    @objc private func close(_ sender: Any?) {
        onClose?()
    }

    private func updateResultLabel() {
        if let selected {
            resultLabel.stringValue = "\(selected + 1)/\(total.map(String.init) ?? "?")"
        } else if let total {
            resultLabel.stringValue = "-/\(total)"
        } else {
            resultLabel.stringValue = ""
        }
    }

    private static func makeButton(symbol: String, label: String) -> NSButton {
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        ) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        updateButton(button, label: label)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private static func updateButton(_ button: NSButton, label: String) {
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
}
