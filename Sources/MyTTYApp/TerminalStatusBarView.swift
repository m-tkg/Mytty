import AppKit
import Combine
import MyTTYCore
import SwiftUI

enum TerminalStatusBarTrailingItem: Hashable {
    case agent
    case sleepPrevention
    case scheduledInput
}

enum TerminalStatusBarLayout {
    static let trailingUsesIntrinsicWidth = true
    static let trailingItems: [TerminalStatusBarTrailingItem] = [
        .agent,
        .sleepPrevention,
        .scheduledInput,
    ]
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
        scheduledInputCount: Int = 0
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
        onDeleteScheduledInput: @escaping (PaneInputSchedule) -> Void = { _ in }
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

                            if let branchName = model.content.branchName {
                                Text(branchName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
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
        }
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
            .help(localizer[.copySessionID])
            .accessibilityLabel(agent)
        } else {
            Label(agent, systemImage: "sparkles")
                .lineLimit(1)
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
                .frame(maxWidth: 60)

            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.16))

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.55))
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
                    .foregroundStyle(.primary)
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
        .accessibilityValue(localizer.remainingPercent(content.percent))
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
