import AppKit
import WebKit

struct BrowserFindLabels: Equatable {
    var placeholder = "Find"
    var previousMatch = "Previous match"
    var nextMatch = "Next match"
    var closeSearch = "Close search"
    var matchFound = "Match"
    var noMatches = "No matches"
}

@MainActor
final class BrowserPaneView: NSView, NSTextFieldDelegate, WKNavigationDelegate,
    WKUIDelegate {
    var onURLChanged: ((URL) -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onFocus: (() -> Void)? {
        didSet { webView.onFocus = onFocus }
    }
    var onCommandClickLink: ((URL, NSView) -> Void)?
    var onClose: (() -> Void)?

    private let backButton: NSButton
    private let forwardButton: NSButton
    private let reloadButton: NSButton
    private let closeButton: NSButton
    private let addressField = NSTextField()
    private let webView: FocusableWebView
    private let findBar: BrowserFindBarView
    private var currentURL: URL
    private var shortcutMonitor: Any?
    private var findRequestID = 0

    private(set) var isFindPresented = false

    init(
        url: URL,
        closeAccessibilityLabel: String = "Close Browser",
        findLabels: BrowserFindLabels = BrowserFindLabels()
    ) {
        currentURL = url
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent =
            Self.applicationNameForUserAgent(
                macOSMajorVersion: ProcessInfo.processInfo
                    .operatingSystemVersion.majorVersion
            )
        webView = FocusableWebView(
            frame: .zero,
            configuration: configuration
        )
        backButton = Self.makeToolbarButton(
            symbol: "chevron.left",
            accessibilityLabel: "Back"
        )
        forwardButton = Self.makeToolbarButton(
            symbol: "chevron.right",
            accessibilityLabel: "Forward"
        )
        reloadButton = Self.makeToolbarButton(
            symbol: "arrow.clockwise",
            accessibilityLabel: "Reload"
        )
        closeButton = Self.makeToolbarButton(
            symbol: "xmark",
            accessibilityLabel: closeAccessibilityLabel
        )
        findBar = BrowserFindBarView(labels: findLabels)
        super.init(frame: .zero)

        configureView()
        load(url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        guard window != nil else { return }

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self,
                  let window = self.window
            else { return event }
            return self.routeApplicationShortcut(
                event,
                firstResponder: window.firstResponder
            ) ? nil : event
        }
    }

    func focusContent() {
        window?.makeFirstResponder(webView)
    }

    func showFind() {
        isFindPresented = true
        findBar.isHidden = false
        findBar.focusField()
        if !findBar.query.isEmpty {
            performFind(backwards: false)
        }
    }

    func closeFind() {
        guard isFindPresented else { return }
        isFindPresented = false
        findBar.isHidden = true
        findBar.matchFound = nil
        clearFind()
        focusContent()
    }

    func updateFindLabels(_ labels: BrowserFindLabels) {
        findBar.update(labels: labels)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.routesToApplicationMenu {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func routeApplicationShortcut(
        _ event: NSEvent,
        firstResponder: NSResponder?
    ) -> Bool {
        guard containsFirstResponder(firstResponder) else { return false }
        return event.routesToApplicationMenu
    }

    func containsFirstResponder(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return view === self || view.isDescendant(of: self)
    }

    func load(_ url: URL) {
        currentURL = url
        addressField.stringValue = url.isFileURL ? url.path : url.absoluteString
        switch BrowserLoadPlan(url: url) {
        case let .file(file, readAccess):
            webView.loadFileURL(file, allowingReadAccessTo: readAccess)
        case let .request(request):
            webView.load(request)
        }
        updateNavigationButtons()
    }

    private func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let toolbar = NSVisualEffectView()
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active

        backButton.target = self
        backButton.action = #selector(goBack(_:))
        forwardButton.target = self
        forwardButton.action = #selector(goForward(_:))
        reloadButton.target = self
        reloadButton.action = #selector(reload(_:))
        closeButton.target = self
        closeButton.action = #selector(closeBrowser(_:))

        addressField.delegate = self
        addressField.placeholderString = "URL or HTML file path"
        addressField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        addressField.focusRingType = .exterior
        addressField.target = self
        addressField.action = #selector(commitAddress(_:))

        webView.navigationDelegate = self
        webView.uiDelegate = self
        findBar.isHidden = true
        findBar.onFocus = { [weak self] in self?.onFocus?() }
        findBar.onQueryChanged = { [weak self] in
            self?.performFind(backwards: false)
        }
        findBar.onPrevious = { [weak self] in
            self?.performFind(backwards: true)
        }
        findBar.onNext = { [weak self] in
            self?.performFind(backwards: false)
        }
        findBar.onClose = { [weak self] in self?.closeFind() }

        let stack = NSStackView(
            views: [
                backButton,
                forwardButton,
                reloadButton,
                addressField,
                closeButton,
            ]
        )
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        findBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(toolbar)
        toolbar.addSubview(stack)
        addSubview(webView)
        addSubview(findBar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 28),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            findBar.topAnchor.constraint(
                equalTo: toolbar.bottomAnchor,
                constant: 8
            ),
            findBar.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            findBar.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 8
            ),
            findBar.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }

    private func performFind(backwards: Bool) {
        let query = findBar.query
        findBar.matchFound = nil
        guard !query.isEmpty else {
            clearFind()
            return
        }

        findRequestID += 1
        let requestID = findRequestID
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) {
            [weak self] result in
            guard let self, requestID == self.findRequestID else { return }
            self.findBar.matchFound = result.matchFound
        }
    }

    private func clearFind() {
        findRequestID += 1
        let configuration = WKFindConfiguration()
        webView.find("", configuration: configuration) { _ in }
    }

    /// A bare WKWebView sends no `Version/… Safari/…` suffix, so sites
    /// treat the pane as an embedded WebView and some (Google sign-in,
    /// "unsupported browser" walls) refuse it. Claim the Safari that ships
    /// with the running macOS: Safari and macOS share the marketing
    /// version since 26; the macOS 15 baseline shipped Safari 18.
    nonisolated static func applicationNameForUserAgent(
        macOSMajorVersion: Int
    ) -> String {
        let safariMajorVersion = macOSMajorVersion >= 26
            ? macOSMajorVersion
            : 18
        return "Version/\(safariMajorVersion).0 Safari/605.1.15"
    }

    private static func makeToolbarButton(
        symbol: String,
        accessibilityLabel: String
    ) -> NSButton {
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityLabel
        ) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func goBack(_ sender: Any?) {
        webView.goBack()
    }

    @objc private func goForward(_ sender: Any?) {
        webView.goForward()
    }

    @objc private func reload(_ sender: Any?) {
        webView.reload()
    }

    @objc private func closeBrowser(_ sender: Any?) {
        onClose?()
    }

    @objc private func commitAddress(_ sender: Any?) {
        let base = currentURL.isFileURL
            ? currentURL.deletingLastPathComponent()
            : FileManager.default.homeDirectoryForCurrentUser
        guard let url = BrowserAddress.resolve(
            addressField.stringValue,
            relativeTo: base
        ) else { return }
        load(url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.modifierFlags.contains(.command),
           navigationAction.navigationType == .linkActivated {
            onCommandClickLink?(url, webView)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            load(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            currentURL = url
            addressField.stringValue = url.isFileURL
                ? url.path
                : url.absoluteString
            onURLChanged?(url)
        }
        onTitleChanged?(webView.title ?? "")
        updateNavigationButtons()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        updateNavigationButtons()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }
}

@MainActor
private final class BrowserFindBarView: NSVisualEffectView,
    NSSearchFieldDelegate {
    var onFocus: (() -> Void)?
    var onQueryChanged: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?

    var query: String { searchField.stringValue }
    var matchFound: Bool? {
        didSet { updateResultLabel() }
    }

    private let searchField = NSSearchField()
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton: NSButton
    private let nextButton: NSButton
    private let closeButton: NSButton
    private var labels: BrowserFindLabels

    init(labels: BrowserFindLabels) {
        self.labels = labels
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

        resultLabel.font = .systemFont(
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
        fatalError("init(coder:) has not been implemented")
    }

    func update(labels: BrowserFindLabels) {
        self.labels = labels
        searchField.placeholderString = labels.placeholder
        Self.updateButton(previousButton, label: labels.previousMatch)
        Self.updateButton(nextButton, label: labels.nextMatch)
        Self.updateButton(closeButton, label: labels.closeSearch)
        updateResultLabel()
    }

    func focusField() {
        onFocus?()
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        onFocus?()
    }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChanged?()
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
        switch matchFound {
        case true:
            resultLabel.stringValue = labels.matchFound
        case false:
            resultLabel.stringValue = labels.noMatches
        case nil:
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

@MainActor
private final class FocusableWebView: WKWebView {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.routesToApplicationMenu {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private extension NSEvent {
    var routesToApplicationMenu: Bool {
        guard type == .keyDown,
              !modifierFlags.intersection([
                  .command,
                  .control,
                  .option,
              ]).isEmpty
        else { return false }
        return NSApplication.shared.mainMenu?
            .performKeyEquivalent(with: self) == true
    }
}
