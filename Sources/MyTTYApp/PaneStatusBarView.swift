import AppKit

/// The thin bar along the top of a terminal pane: repository mark, branch,
/// agent, and either the agent's session ID or the foreground program's name.
///
/// AppKit rather than SwiftUI on purpose — it is a sibling of the Ghostty
/// surface inside `PaneHostView`, like the remote pane's header, and its
/// labels have to be pinned to a very low horizontal priority so a long
/// branch name can never pull an `NSSplitView` divider off the stored ratio.
@MainActor
final class PaneStatusBarView: NSView {
    static let height: CGFloat = 20

    private let repositoryMark = NSImageView()
    private let branchLabel = NSTextField(labelWithString: "")
    private let agentLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")
    private let separator = NSView()
    private var repositoryURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureView() {
        wantsLayer = true

        repositoryMark.imageScaling = .scaleProportionallyUpOrDown
        repositoryMark.isHidden = true
        repositoryMark.addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(openRepository))
        )

        for label in [branchLabel, agentLabel, trailingLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.isHidden = true
            // The chrome must never dictate the pane's width: a label's
            // default hugging and compression resistance (750) outranks
            // NSSplitView's divider position, so a long branch name would
            // otherwise push the divider off the stored ratio. Truncating is
            // the right outcome here.
            label.setContentCompressionResistancePriority(
                NSLayoutConstraint.Priority(100),
                for: .horizontal
            )
            label.setContentHuggingPriority(
                NSLayoutConstraint.Priority(100),
                for: .horizontal
            )
        }
        agentLabel.font = .systemFont(ofSize: 11, weight: .medium)
        trailingLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        for subview in [repositoryMark, branchLabel, agentLabel, trailingLabel, separator] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        separator.wantsLayer = true

        NSLayoutConstraint.activate([
            repositoryMark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            repositoryMark.centerYAnchor.constraint(equalTo: centerYAnchor),
            repositoryMark.widthAnchor.constraint(equalToConstant: 12),
            repositoryMark.heightAnchor.constraint(equalToConstant: 12),

            branchLabel.leadingAnchor.constraint(
                equalTo: repositoryMark.trailingAnchor,
                constant: 5
            ),
            branchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            agentLabel.leadingAnchor.constraint(
                equalTo: branchLabel.trailingAnchor,
                constant: 8
            ),
            agentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingLabel.leadingAnchor.constraint(
                equalTo: agentLabel.trailingAnchor,
                constant: 8
            ),
            trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -6
            ),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        updateColors()
    }

    func apply(_ content: PaneStatusBarContent, labels: PaneStatusBarLabels) {
        repositoryURL = content.repositoryURL
        repositoryMark.isHidden = content.repositoryURL == nil
        if content.repositoryURL != nil, repositoryMark.image == nil {
            repositoryMark.image = GitHubMarkImageSource.imageOrFallback(
                accessibilityDescription: labels.openOnGitHub
            )
        }
        repositoryMark.toolTip = labels.openOnGitHub
        repositoryMark.setAccessibilityLabel(labels.openOnGitHub)

        apply(content.branchName, to: branchLabel)
        branchLabel.setAccessibilityLabel(labels.branch)
        apply(content.agentName, to: agentLabel)
        apply(content.trailingText, to: trailingLabel)

        toolTip = content.tooltip
        for label in [branchLabel, agentLabel, trailingLabel] {
            label.toolTip = content.tooltip
        }
    }

    private func apply(_ text: String?, to label: NSTextField) {
        label.stringValue = text ?? ""
        label.isHidden = text == nil
    }

    /// Everything the bar is currently showing, in reading order — the
    /// rendered counterpart of `PaneStatusBarContent`, for tests.
    var displayedText: String {
        [branchLabel, agentLabel, trailingLabel]
            .filter { !$0.isHidden }
            .map(\.stringValue)
            .joined(separator: " ")
    }

    var isRepositoryMarkVisible: Bool { !repositoryMark.isHidden }

    @objc private func openRepository() {
        guard let repositoryURL else { return }
        NSWorkspace.shared.open(repositoryURL)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Resolved CGColors don't follow the appearance on their own.
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        repositoryMark.contentTintColor = .secondaryLabelColor
    }
}
