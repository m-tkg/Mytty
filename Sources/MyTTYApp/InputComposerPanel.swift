import AppKit
import MyTTYCore

/// Floating panel for composing multi-line input: a plain-text editor and
/// a Send button that delivers the full text to the focused terminal pane
/// in one paste-like shot (see `GhosttySurfaceView.sendText`). Modeled on
/// `OneLinerPanelController`.
@MainActor
final class InputComposerPanelController: NSObject {
    private let panel: NSPanel
    private let textView: NSTextView
    private let statusLabel: NSTextField
    private let sendButton: NSButton
    private let localizer: MyTTYLocalizer
    private let send: (String) -> Bool

    init(
        localizer: MyTTYLocalizer,
        send: @escaping (String) -> Bool
    ) {
        self.localizer = localizer
        self.send = send

        let contentRect = NSRect(x: 0, y: 0, width: 560, height: 240)
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = localizer[.composeInput]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextView()
        text.isRichText = false
        text.allowsUndo = true
        text.isEditable = true
        text.isSelectable = true
        text.font = .monospacedSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular
        )
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        textView = text

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        sendButton = NSButton(
            title: localizer[.inputComposerSend], target: nil, action: nil
        )
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = [.command]
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        super.init()
        sendButton.target = self
        sendButton.action = #selector(sendButtonPressed(_:))

        let content = NSView(frame: contentRect)
        content.addSubview(scroll)
        content.addSubview(statusLabel)
        content.addSubview(sendButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(
                equalTo: content.topAnchor, constant: 12
            ),
            scroll.leadingAnchor.constraint(
                equalTo: content.leadingAnchor, constant: 12
            ),
            scroll.trailingAnchor.constraint(
                equalTo: content.trailingAnchor, constant: -12
            ),
            scroll.bottomAnchor.constraint(
                equalTo: statusLabel.topAnchor, constant: -8
            ),

            statusLabel.leadingAnchor.constraint(
                equalTo: content.leadingAnchor, constant: 12
            ),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: sendButton.leadingAnchor, constant: -12
            ),
            statusLabel.bottomAnchor.constraint(
                equalTo: content.bottomAnchor, constant: -12
            ),

            sendButton.trailingAnchor.constraint(
                equalTo: content.trailingAnchor, constant: -12
            ),
            sendButton.bottomAnchor.constraint(
                equalTo: content.bottomAnchor, constant: -12
            ),
        ])

        panel.contentView = content
        panel.initialFirstResponder = text
        panel.setContentSize(NSSize(width: 560, height: 240))
        panel.minSize = NSSize(width: 360, height: 160)
    }

    func show() {
        if !panel.isVisible {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    func close() {
        panel.close()
    }

    /// Reads the composer's text and sends it to the focused pane. A
    /// successful send clears the draft and closes the panel; a failed
    /// send (no terminal pane focused) keeps the draft and surfaces a
    /// status message so the user can refocus a pane and retry. No-op on
    /// an empty draft.
    func sendCurrentText() {
        let text = textView.string
        guard !text.isEmpty else { return }
        if send(text) {
            textView.string = ""
            statusLabel.stringValue = ""
            panel.close()
        } else {
            statusLabel.stringValue = localizer[.inputComposerNoTerminalPane]
        }
    }

    @objc private func sendButtonPressed(_ sender: Any?) {
        sendCurrentText()
    }

    // MARK: - Test seams

    var draftText: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    var isPanelVisible: Bool { panel.isVisible }

    var statusText: String { statusLabel.stringValue }
}
