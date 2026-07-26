import AppKit
import MyTTYCore
import MyTTYRemoteKit

/// The strings a remote pane draws in its own chrome. Passed in rather than
/// read from a global so the view stays testable and the localizer keeps
/// living with the rest of the app's UI.
struct RemotePaneLabels: Equatable {
    var remoteBadge = "Remote"
    var close = "Close Remote Pane"
    var needsAttention = "Needs attention"
    var connecting = "Connecting…"
    var disconnected = "Disconnected"
    var reconnect = "Reconnect"
    var inputDisabled = "Input is disabled until reconnected."
    var paneClosedOnHost = "This pane is no longer open on the host."
}

/// A pane mirroring one terminal on another Mac.
///
/// Everything visible here comes over the remote protocol, so the pane
/// wears its own chrome — a badge naming the host — and never pretends to
/// be a local terminal. That is the point of it being a separate pane kind:
/// agent status polling, repository status and mytty-ctl all skip it, and
/// the status bar shows the host instead of a local working directory.
@MainActor
final class RemotePaneView: NSView {
    var onFocus: (() -> Void)?
    var onClose: (() -> Void)?
    /// Fired when the host reports a different title for the mirrored pane,
    /// so the tab can follow it the way it follows a local pane's command.
    var onTitleChanged: ((String) -> Void)?
    /// Input the user produced in this pane, for the owner to put on the
    /// wire. The view itself holds no connection.
    var onSendText: ((String) -> Void)?
    var onSendKey: ((String, [String]) -> Void)?
    var onSendScroll: ((Double) -> Void)?
    var onReconnect: (() -> Void)?

    let paneID: TerminalSurfaceID
    let hostID: String
    let remotePaneID: String

    private let labels: RemotePaneLabels
    private var hostName: String
    private var title: String

    private let badgeLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let agentLabel = NSTextField(labelWithString: "")
    private let attentionDot = NSImageView()
    private let closeButton: NSButton
    private let scrollView = NSScrollView()
    private let screenView: RemotePaneScreenView
    private let bannerView = NSView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let reconnectButton: NSButton
    private let compositionLabel = NSTextField(labelWithString: "")
    private var bannerHeight: NSLayoutConstraint?
    private var compositionHeight: NSLayoutConstraint?

    private var state: RemoteClient.ConnectionState = .disconnected
    /// The host's own view of the agent in the mirrored pane. A client
    /// cannot see the process or read the transcript, so this is the only
    /// source for it.
    private var agent: RemotePaneAgentStatus?
    /// True once a live snapshot has been seen that no longer lists this
    /// pane — the host closed it, and no reconnect will bring it back.
    private var isGoneOnHost = false

    init(
        paneID: TerminalSurfaceID,
        hostID: String,
        remotePaneID: String,
        hostName: String,
        title: String,
        font: NSFont,
        labels: RemotePaneLabels = RemotePaneLabels()
    ) {
        self.paneID = paneID
        self.hostID = hostID
        self.remotePaneID = remotePaneID
        self.hostName = hostName
        self.title = title
        self.labels = labels
        screenView = RemotePaneScreenView(font: font)
        closeButton = Self.makeChromeButton(
            symbol: "xmark",
            accessibilityLabel: labels.close
        )
        reconnectButton = NSButton(title: labels.reconnect, target: nil, action: nil)
        super.init(frame: .zero)
        configureView()
        refreshChrome()
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Owner-facing updates

    /// Replaces the mirrored screen. Passing nil keeps whatever was last
    /// drawn: a reconnect drops the host's content, and blanking the pane
    /// would be a worse answer than showing the last frame dimmed behind
    /// the disconnected banner.
    func update(screen: RemoteClient.PaneScreen?) {
        guard let screen else { return }
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: screen.text,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
            styledLines: screen.styledLines
        )
        let wasAtBottom = isScrolledToBottom
        screenView.update(
            lines: lines,
            plainText: screen.text,
            isAltScreen: screen.altScreen
        )
        // Follow new output only while the user is already at the bottom,
        // so a screen update never yanks the view down mid-read.
        if wasAtBottom { scrollToBottom() }
    }

    func update(state: RemoteClient.ConnectionState) {
        guard state != self.state else { return }
        self.state = state
        applyState()
    }

    func update(title: String) {
        guard title != self.title else { return }
        self.title = title
        refreshChrome()
        onTitleChanged?(title)
    }

    func update(hostName: String) {
        guard hostName != self.hostName else { return }
        self.hostName = hostName
        refreshChrome()
    }

    func update(font: NSFont) {
        screenView.update(font: font)
    }

    func update(agent: RemotePaneAgentStatus?) {
        guard agent != self.agent else { return }
        self.agent = agent
        refreshChrome()
    }

    /// Marks the pane as gone: the host is connected and its snapshot no
    /// longer lists this pane. The mirrored content stays on screen so the
    /// user can still read and copy it, but input is off for good.
    func markClosedOnHost() {
        guard !isGoneOnHost else { return }
        isGoneOnHost = true
        applyState()
    }

    var isConnected: Bool { state == .connected && !isGoneOnHost }

    /// The viewport size in cells, which the owner reports to the host.
    var visibleGridSize: (columns: Int, rows: Int) {
        screenView.visibleGridSize
    }

    func focusScreen() {
        window?.makeFirstResponder(screenView)
    }

    // MARK: - Layout

    private func configureView() {
        wantsLayer = true

        let header = makeHeader()
        configureBanner()
        configureComposition()
        configureScrollView()

        // The chrome labels must never dictate the pane's width: their
        // default hugging and compression resistance (750) outrank
        // NSSplitView's divider position, so a label pinned to both edges
        // (composition) pulls the pane toward its own text width and a
        // long title pushes the divider off the stored ratio. Truncating
        // or stretching is the right outcome for all of them.
        for label in [
            badgeLabel, titleLabel, agentLabel, bannerLabel, compositionLabel,
        ] {
            label.setContentCompressionResistancePriority(
                NSLayoutConstraint.Priority(100),
                for: .horizontal
            )
            label.setContentHuggingPriority(
                NSLayoutConstraint.Priority(100),
                for: .horizontal
            )
        }

        for subview in [header, bannerView, scrollView, compositionLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),

            bannerView.topAnchor.constraint(equalTo: header.bottomAnchor),
            bannerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: bannerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            compositionLabel.topAnchor.constraint(
                equalTo: scrollView.bottomAnchor
            ),
            compositionLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 8
            ),
            compositionLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            compositionLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        bannerHeight = bannerView.heightAnchor.constraint(equalToConstant: 0)
        bannerHeight?.isActive = true
        compositionHeight = compositionLabel.heightAnchor
            .constraint(equalToConstant: 0)
        compositionHeight?.isActive = true
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.textColor = .white
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.systemIndigo.cgColor
        badgeLabel.layer?.cornerRadius = 3
        badgeLabel.alignment = .center

        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        agentLabel.font = .systemFont(ofSize: 11, weight: .medium)
        agentLabel.textColor = .secondaryLabelColor
        agentLabel.lineBreakMode = .byTruncatingTail

        attentionDot.image = NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: labels.needsAttention
        )
        attentionDot.contentTintColor = .systemOrange
        attentionDot.isHidden = true
        attentionDot.setAccessibilityLabel(labels.needsAttention)

        for subview in [
            badgeLabel, titleLabel, agentLabel, attentionDot, closeButton,
        ] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(
                equalTo: header.leadingAnchor,
                constant: 6
            ),
            badgeLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            badgeLabel.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(
                equalTo: badgeLabel.trailingAnchor,
                constant: 6
            ),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: agentLabel.leadingAnchor,
                constant: -6
            ),

            agentLabel.trailingAnchor.constraint(
                equalTo: attentionDot.leadingAnchor,
                constant: -4
            ),
            agentLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            attentionDot.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor,
                constant: -4
            ),
            attentionDot.centerYAnchor.constraint(
                equalTo: header.centerYAnchor
            ),
            attentionDot.widthAnchor.constraint(equalToConstant: 12),
            attentionDot.heightAnchor.constraint(equalToConstant: 12),

            closeButton.trailingAnchor.constraint(
                equalTo: header.trailingAnchor,
                constant: -4
            ),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
        return header
    }

    private func configureBanner() {
        bannerView.wantsLayer = true
        bannerView.layer?.backgroundColor = NSColor.systemRed
            .withAlphaComponent(0.9).cgColor

        bannerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        bannerLabel.textColor = .white
        bannerLabel.lineBreakMode = .byTruncatingTail

        reconnectButton.target = self
        reconnectButton.action = #selector(reconnectClicked)
        reconnectButton.controlSize = .small
        reconnectButton.bezelStyle = .rounded

        for subview in [bannerLabel, reconnectButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            bannerView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            bannerLabel.leadingAnchor.constraint(
                equalTo: bannerView.leadingAnchor,
                constant: 8
            ),
            bannerLabel.centerYAnchor.constraint(
                equalTo: bannerView.centerYAnchor
            ),
            bannerLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: reconnectButton.leadingAnchor,
                constant: -8
            ),
            reconnectButton.trailingAnchor.constraint(
                equalTo: bannerView.trailingAnchor,
                constant: -8
            ),
            reconnectButton.centerYAnchor.constraint(
                equalTo: bannerView.centerYAnchor
            ),
        ])
    }

    private func configureComposition() {
        compositionLabel.font = .systemFont(ofSize: 12)
        compositionLabel.lineBreakMode = .byTruncatingTail
        compositionLabel.textColor = .labelColor
        compositionLabel.wantsLayer = true
        compositionLabel.layer?.backgroundColor = NSColor
            .underPageBackgroundColor.cgColor
        screenView.onCompositionChanged = { [weak self] composition in
            self?.showComposition(composition)
        }
    }

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = screenView

        screenView.onSendText = { [weak self] text in
            self?.onSendText?(text)
        }
        screenView.onSendKey = { [weak self] key, modifiers in
            self?.onSendKey?(key, modifiers)
        }
        screenView.onSendScroll = { [weak self] delta in
            self?.onSendScroll?(delta)
        }
        screenView.onFocusChanged = { [weak self] focused in
            if focused { self?.onFocus?() }
        }
    }

    private static func makeChromeButton(
        symbol: String,
        accessibilityLabel: String
    ) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityLabel
        )
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    // MARK: - State

    private func refreshChrome() {
        badgeLabel.stringValue = " \(labels.remoteBadge): \(hostName) "
        titleLabel.stringValue = title
        titleLabel.toolTip = title
        agentLabel.stringValue = agentSummary
        attentionDot.isHidden = agent?.needsAttention != true
    }

    /// The agent line in the header: what is running on the host and, when
    /// it reports one, the model. Empty when the host sends no agent
    /// status — including when it is too old to send any.
    private var agentSummary: String {
        guard let agent else { return "" }
        let parts = [
            RemoteAgentDisplay.providerName(agent.provider),
            agent.modelName,
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private func applyState() {
        let connected = isConnected
        screenView.setInputEnabled(connected)
        // Dim stale content so it reads as a frozen mirror rather than a
        // live screen the user could be typing into.
        screenView.alphaValue = connected ? 1 : 0.5

        if connected {
            bannerHeight?.constant = 0
            bannerView.isHidden = true
            return
        }
        bannerView.isHidden = false
        bannerHeight?.constant = 28
        reconnectButton.isHidden = isGoneOnHost
        bannerLabel.stringValue = bannerMessage
    }

    private var bannerMessage: String {
        if isGoneOnHost { return labels.paneClosedOnHost }
        switch state {
        case .connecting:
            return labels.connecting
        case let .failed(message):
            return "\(labels.disconnected) — \(message)"
        default:
            return "\(labels.disconnected). \(labels.inputDisabled)"
        }
    }

    private func showComposition(_ composition: String) {
        compositionLabel.stringValue = composition
        compositionHeight?.constant = composition.isEmpty ? 0 : 20
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func reconnectClicked() {
        onReconnect?()
    }

    // MARK: - Scrolling

    private var isScrolledToBottom: Bool {
        let visible = scrollView.documentVisibleRect
        let contentHeight = screenView.frame.height
        // Slack of a couple of lines, so sub-pixel wiggle from a resize
        // does not read as "the user scrolled up".
        return visible.maxY >= contentHeight - 24
    }

    private func scrollToBottom() {
        let contentHeight = screenView.frame.height
        let viewportHeight = scrollView.contentView.bounds.height
        guard contentHeight > viewportHeight else { return }
        screenView.scroll(
            NSPoint(x: 0, y: contentHeight - viewportHeight)
        )
    }
}
