import AppKit
import Combine
import MyTTYCore
import SwiftUI

/// `.help` takes a non-optional `String`; this only attaches the modifier
/// when there's actually a tooltip to show.
private extension View {
    @ViewBuilder
    func optionalHelp(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}

enum TerminalStatusBarTrailingItem: Hashable {
    case agent
    case sleepPrevention
    case scheduledInput
    case bookmarks
}

enum TerminalStatusBarLayout {
    static let trailingUsesIntrinsicWidth = true
    static let trailingItems: [TerminalStatusBarTrailingItem] = [
        .agent,
        .sleepPrevention,
        .scheduledInput,
        .bookmarks,
    ]
}

/// A focused pane's line bookmark, as shown in the status bar menu.
struct BookmarkDisplayItem: Equatable, Hashable {
    let id: UUID
    let snippet: String
}

struct TerminalStatusBarContent: Equatable {
    var resource: String
    var resourceSymbolName: String
    var canRevealInFinder: Bool
    var repositoryURL: URL?
    var branchName: String?
    var agentName: String?
    var agentSessionID: String?
    var agentModelName: String?
    var agentState: String?
    var agentUsage: AgentUsageStatusContent?
    var agentContext: AgentUsageMeterContent?
    var sleepStatus: AgentSleepStatus
    var canScheduleInput: Bool
    var scheduledInputCount: Int
    var bookmarks: [BookmarkDisplayItem]

    init(
        resource: String = "",
        resourceSymbolName: String = "folder",
        canRevealInFinder: Bool = false,
        repositoryURL: URL? = nil,
        branchName: String? = nil,
        agentName: String? = nil,
        agentSessionID: String? = nil,
        agentModelName: String? = nil,
        agentState: String? = nil,
        agentUsage: AgentUsageStatusContent? = nil,
        agentContext: AgentUsageMeterContent? = nil,
        sleepStatus: AgentSleepStatus = .disabled,
        canScheduleInput: Bool = false,
        scheduledInputCount: Int = 0,
        bookmarks: [BookmarkDisplayItem] = []
    ) {
        self.resource = resource
        self.resourceSymbolName = resourceSymbolName
        self.canRevealInFinder = canRevealInFinder
        self.repositoryURL = repositoryURL
        self.branchName = branchName
        self.agentName = agentName
        self.agentSessionID = agentSessionID
        self.agentModelName = agentModelName
        self.agentState = agentState
        self.agentUsage = agentUsage
        self.agentContext = agentContext
        self.sleepStatus = sleepStatus
        self.canScheduleInput = canScheduleInput
        self.scheduledInputCount = scheduledInputCount
        self.bookmarks = bookmarks
    }

    var agentDescription: String? {
        guard let agentName else { return nil }
        return ([
            agentName,
            agentModelName,
            agentState,
            agentUsage?.costDescription,
        ]
            .compactMap { $0 })
            .joined(separator: " · ")
    }

    var visibleAgentUsageLimits: [AgentUsageMeterContent] {
        guard agentName != nil else { return [] }
        return [agentContext].compactMap { $0 } + (agentUsage?.limits ?? [])
    }

    var copyableAgentSessionID: String? {
        guard agentName != nil else { return nil }
        return agentSessionID
    }
}

@MainActor
final class TerminalStatusBarModel: ObservableObject {
    @Published var content = TerminalStatusBarContent()
    @Published var schedules: [PaneInputSchedule] = []

    func updateScheduledInputs(
        _ schedules: [PaneInputSchedule],
        focusedSurfaceID: TerminalSurfaceID?,
        isTerminalPane: Bool
    ) {
        guard isTerminalPane, let focusedSurfaceID else {
            self.schedules = []
            content.canScheduleInput = false
            content.scheduledInputCount = 0
            return
        }
        let visible = schedules.filter {
            $0.surfaceID == focusedSurfaceID
        }
        self.schedules = visible
        content.canScheduleInput = true
        content.scheduledInputCount = visible.count
    }

    /// `items` is already the focused pane's bookmarks (the coordinator
    /// stores them per-pane); `isTerminalPane` still gates display the
    /// same way `updateScheduledInputs` does, so a browser/remote pane or
    /// no selected tab shows none.
    func updateBookmarks(
        _ items: [BookmarkDisplayItem],
        isTerminalPane: Bool
    ) {
        content.bookmarks = isTerminalPane ? items : []
    }
}

struct TerminalStatusBarView: View {
    @ObservedObject var model: TerminalStatusBarModel
    let revealInFinderTitle: String
    let onRevealInFinder: () -> Void
    let openRepositoryTitle: String
    let onOpenRepository: () -> Void
    let localizer: MyTTYLocalizer
    let onSelectSleepPreventionMode: (AgentSleepPreventionMode) -> Void
    let onNewScheduledInput: () -> Void
    let onEditScheduledInput: (PaneInputSchedule) -> Void
    let onDeleteScheduledInput: (PaneInputSchedule) -> Void
    let onSelectBookmark: (UUID) -> Void
    let onDeleteBookmark: (UUID) -> Void

    init(
        model: TerminalStatusBarModel,
        revealInFinderTitle: String,
        onRevealInFinder: @escaping () -> Void,
        openRepositoryTitle: String = "Open on GitHub",
        onOpenRepository: @escaping () -> Void = {},
        localizer: MyTTYLocalizer = MyTTYLocalizer(language: .english),
        onSelectSleepPreventionMode: @escaping (AgentSleepPreventionMode) -> Void = { _ in },
        onNewScheduledInput: @escaping () -> Void = {},
        onEditScheduledInput: @escaping (PaneInputSchedule) -> Void = { _ in },
        onDeleteScheduledInput: @escaping (PaneInputSchedule) -> Void = { _ in },
        onSelectBookmark: @escaping (UUID) -> Void = { _ in },
        onDeleteBookmark: @escaping (UUID) -> Void = { _ in }
    ) {
        self.model = model
        self.revealInFinderTitle = revealInFinderTitle
        self.onRevealInFinder = onRevealInFinder
        self.openRepositoryTitle = openRepositoryTitle
        self.onOpenRepository = onOpenRepository
        self.localizer = localizer
        self.onSelectSleepPreventionMode = onSelectSleepPreventionMode
        self.onNewScheduledInput = onNewScheduledInput
        self.onEditScheduledInput = onEditScheduledInput
        self.onDeleteScheduledInput = onDeleteScheduledInput
        self.onSelectBookmark = onSelectBookmark
        self.onDeleteBookmark = onDeleteBookmark
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if !model.content.resource.isEmpty {
                    HStack(spacing: 4) {
                        if model.content.repositoryURL != nil {
                            Button(action: openRepository) {
                                GitHubMarkImage()
                                    .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                            .help(openRepositoryTitle)
                            .accessibilityLabel(openRepositoryTitle)
                        }
                        if let branchName = model.content.branchName {
                            Image(systemName: "arrow.triangle.branch")
                                .frame(width: 14, height: 14)
                            Text(branchName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if model.content.canRevealInFinder {
                            Button(action: revealResourceInFinder) {
                                Image(
                                    systemName: model.content.resourceSymbolName
                                )
                                .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help(revealInFinderTitle)
                            .accessibilityLabel(revealInFinderTitle)
                        } else {
                            Image(systemName: model.content.resourceSymbolName)
                                .frame(width: 14, height: 14)
                        }
                        Text(model.content.resource)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    ForEach(
                        TerminalStatusBarLayout.trailingItems,
                        id: \.self
                    ) { item in
                        trailingItem(item)
                    }
                }
                .fixedSize(
                    horizontal:
                        TerminalStatusBarLayout.trailingUsesIntrinsicWidth,
                    vertical: false
                )
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 23)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func trailingItem(
        _ item: TerminalStatusBarTrailingItem
    ) -> some View {
        switch item {
        case .agent:
            if let agent = model.content.agentDescription {
                HStack(spacing: 12) {
                    agentLabel(agent)
                    agentUsageMeters
                }
            }
        case .sleepPrevention:
            Menu {
                // Toggles render with the native menu-item check column;
                // a Label's systemImage checkmark is dropped from menu
                // items on some SDKs, which hid the selection entirely.
                ForEach(
                    AgentSleepPreventionMode.allCases,
                    id: \.self
                ) { mode in
                    Toggle(
                        localizer[mode.menuLabel],
                        isOn: Binding(
                            get: {
                                mode == model.content.sleepStatus.mode
                            },
                            set: { _ in
                                onSelectSleepPreventionMode(mode)
                            }
                        )
                    )
                }
            } label: {
                Image(systemName: model.content.sleepStatus.symbolName)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            // The borderless menu draws its label with the tint color, so
            // foregroundStyle on the image is ignored — tint the whole
            // control orange while the lid-closed override is armed so the
            // system-wide no-sleep switch is obvious at a glance.
            .tint(
                model.content.sleepStatus.keepsLidClosedAwake
                    ? Color.orange
                    : Color.primary
            )
            .frame(width: 20, height: 20)
            .help(
                model.content.sleepStatus.tooltip(localizer: localizer)
            )
            .accessibilityLabel(
                localizer[.preventSleepWhileAgentRunning]
            )
            .accessibilityValue(
                localizer[model.content.sleepStatus.text]
            )
        case .scheduledInput:
            ScheduledInputMenuButton(
                schedules: model.schedules,
                canCreate: model.content.canScheduleInput,
                localizer: localizer,
                onNew: onNewScheduledInput,
                onEdit: onEditScheduledInput,
                onDelete: onDeleteScheduledInput
            )
            .frame(width: 20, height: 20)
            .help(localizer[.scheduledInput])
        case .bookmarks:
            if !model.content.bookmarks.isEmpty {
                BookmarkMenuButton(
                    bookmarks: model.content.bookmarks,
                    localizer: localizer,
                    onSelect: onSelectBookmark,
                    onDelete: onDeleteBookmark
                )
                .frame(height: 20)
                .help(localizer[.bookmarks])
            }
        }
    }

    /// The plan (if any) plus the existing "Copy Session ID" hint, in that
    /// order — either half may be absent. Shown only in the agent label's
    /// tooltip: the status bar's visible text never widens to fit the plan.
    private var agentLabelTooltip: String? {
        let plan = model.content.agentName != nil
            ? model.content.agentUsage?.planName
            : nil
        let action = model.content.copyableAgentSessionID != nil
            ? localizer[.copySessionID]
            : nil
        let parts = [plan, action].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func agentLabel(_ agent: String) -> some View {
        if model.content.copyableAgentSessionID != nil {
            Menu {
                Button(localizer[.copySessionID]) {
                    copySessionID()
                }
            } label: {
                Label(agent, systemImage: "sparkles")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(
                horizontal:
                    TerminalStatusBarLayout.trailingUsesIntrinsicWidth,
                vertical: false
            )
            .optionalHelp(agentLabelTooltip)
            .accessibilityLabel(agent)
        } else {
            Label(agent, systemImage: "sparkles")
                .lineLimit(1)
                .optionalHelp(agentLabelTooltip)
        }
    }

    private var agentUsageMeters: some View {
        HStack(spacing: 6) {
            ForEach(
                Array(model.content.visibleAgentUsageLimits.enumerated()),
                id: \.offset
            ) { _, limit in
                AgentUsageMeterView(
                    content: limit,
                    localizer: localizer
                )
            }
            if model.content.agentUsage?.onDemandUnavailable == true {
                OnDemandUnavailableBadge(localizer: localizer)
            }
        }
    }

    func revealResourceInFinder() {
        guard model.content.canRevealInFinder else { return }
        onRevealInFinder()
    }

    func openRepository() {
        guard model.content.repositoryURL != nil else { return }
        onOpenRepository()
    }

    func copySessionID(to pasteboard: NSPasteboard = .general) {
        guard let sessionID = model.content.copyableAgentSessionID else {
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(sessionID, forType: .string)
    }
}

private struct AgentUsageMeterView: View {
    let content: AgentUsageMeterContent
    let localizer: MyTTYLocalizer

    var body: some View {
        HStack(spacing: 3) {
            Text(content.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 76)
                .foregroundStyle(content.isLow ? Color.red : Color.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.16))

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        (content.isLow ? Color.red : Color.accentColor)
                            .opacity(0.55)
                    )
                    .frame(width: 44 * content.progress, height: 14)
                    .frame(width: 44, alignment: .leading)

                Text("\(content.percent)%")
                    .font(
                        .system(
                            size: 9,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(content.isLow ? Color.red : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 44, height: 14)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            }
        }
        .opacity(content.isStale ? 0.55 : 1)
        .fixedSize()
        .help(content.tooltip(localizer: localizer))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.title)
        .accessibilityValue(content.accessibilityValue(localizer: localizer))
    }
}

/// Flags a provider quota that reads as "plenty left" while the account
/// can't actually make another request — Cursor's free plan is the case
/// this exists for, see `AgentUsageSummary.onDemandUnavailable`.
private struct OnDemandUnavailableBadge: View {
    let localizer: MyTTYLocalizer

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(Color.orange)
            .help(localizer.onDemandUnavailableBadgeTooltip())
            .accessibilityLabel(localizer.onDemandUnavailableBadgeTooltip())
    }
}

/// Status bar bookmark list. Mirrors `ScheduledInputMenuButton`
/// (`PaneInputSchedulePresentation.swift`): a plain SwiftUI `Menu` can't
/// give a row both a click target and an inline delete button, so this is
/// an `NSViewRepresentable` around a real `NSMenu` with a custom row view
/// per bookmark, same as scheduled inputs' edit/delete rows.
struct BookmarkMenuButton: NSViewRepresentable {
    let bookmarks: [BookmarkDisplayItem]
    let localizer: MyTTYLocalizer
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.showMenu(_:))
        )
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.font = .systemFont(ofSize: 11)
        button.toolTip = localizer[.bookmarks]
        button.setAccessibilityLabel(localizer[.bookmarks])
        updateIndicator(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = localizer[.bookmarks]
        button.setAccessibilityLabel(localizer[.bookmarks])
        updateIndicator(button)
    }

    private func updateIndicator(_ button: NSButton) {
        button.image = NSImage(
            systemSymbolName: bookmarks.isEmpty ? "bookmark" : "bookmark.fill",
            accessibilityDescription: nil
        ) ?? NSImage()
        button.contentTintColor = bookmarks.isEmpty
            ? .secondaryLabelColor
            : .controlAccentColor
        button.title = bookmarks.isEmpty ? "" : "\(bookmarks.count)"
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: BookmarkMenuButton

        init(parent: BookmarkMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu(title: parent.localizer[.bookmarks])
            menu.autoenablesItems = false
            for bookmark in parent.bookmarks {
                let item = NSMenuItem()
                item.view = BookmarkMenuRow(
                    title: bookmark.snippet,
                    deleteAccessibilityLabel: parent.localizer[.delete],
                    onSelect: { [parent] in parent.onSelect(bookmark.id) },
                    onDelete: { [parent] in parent.onDelete(bookmark.id) }
                )
                item.isEnabled = true
                menu.addItem(item)
            }
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 3),
                in: sender
            )
        }
    }
}

@MainActor
private final class BookmarkMenuRow: NSView {
    private let onSelect: () -> Void
    private let onDelete: () -> Void
    private var deferredAction: (() -> Void)?

    init(
        title: String,
        deleteAccessibilityLabel: String,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onDelete = onDelete
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 28))

        let selectButton = NSButton(
            title: title,
            target: self,
            action: #selector(select)
        )
        selectButton.isBordered = false
        selectButton.alignment = .left
        selectButton.lineBreakMode = .byTruncatingTail
        selectButton.contentTintColor = .labelColor
        selectButton.toolTip = title
        selectButton.translatesAutoresizingMaskIntoConstraints = false

        let deleteButton = NSButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                ?? NSImage(),
            target: self,
            action: #selector(delete)
        )
        deleteButton.isBordered = false
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setAccessibilityLabel(deleteAccessibilityLabel)
        toolTip = title

        addSubview(selectButton)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            selectButton.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 10
            ),
            selectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectButton.trailingAnchor.constraint(
                equalTo: deleteButton.leadingAnchor, constant: -6
            ),
            deleteButton.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -8
            ),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func select() {
        performAfterClosingMenu(onSelect)
    }

    @objc private func delete() {
        performAfterClosingMenu(onDelete)
    }

    private func performAfterClosingMenu(
        _ action: @escaping () -> Void
    ) {
        if let menu = enclosingMenuItem?.menu {
            ScheduledInputMenuHierarchy.root(startingAt: menu)
                .cancelTracking()
        }
        deferredAction = action
        let timer = Timer(
            timeInterval: 0,
            target: self,
            selector: #selector(invokeDeferredAction(_:)),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .default)
    }

    @objc private func invokeDeferredAction(_ timer: Timer) {
        let action = deferredAction
        deferredAction = nil
        action?()
    }
}

private struct GitHubMarkImage: View {
    private static let image: NSImage? = {
        guard let url = ApplicationResources.resourceURL(
            named: "mark-github-16",
            withExtension: "svg"
        ), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
        } else {
            Image(systemName: "link")
                .resizable()
        }
    }
}
