import MyTTYCore
import SwiftUI

struct AgentIntegrationSettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var model: AgentIntegrationSettingsModel
    let localizer: MyTTYLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            attentionUnreadOnlyRow

            Divider()
                .padding(.leading, 44)

            sleepPreventionRow

            Divider()
                .padding(.leading, 44)

            ForEach(model.states) { state in
                integrationRow(state)
                if state.id != model.states.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            model.refresh()
        }
    }

    private var attentionUnreadOnlyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer[.attentionUnreadOnly])
                    .font(.system(size: 13, weight: .semibold))
                Text(localizer[.attentionUnreadOnlyDescription])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { settings.application.attentionUnreadOnly },
                    set: { enabled in
                        settings.updateApplication {
                            $0.attentionUnreadOnly = enabled
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(localizer[.attentionUnreadOnly])
        }
        .frame(minHeight: 64)
        .padding(.vertical, 4)
    }

    private var sleepPreventionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer[.preventSleepWhileAgentRunning])
                    .font(.system(size: 13, weight: .semibold))
                Text(localizer[.preventSleepWhileAgentRunningDescription])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(
                "",
                selection: Binding(
                    get: {
                        settings.application.agentSleepPreventionMode
                    },
                    set: { mode in
                        settings.updateApplication {
                            $0.agentSleepPreventionMode = mode
                        }
                    }
                )
            ) {
                ForEach(
                    AgentSleepPreventionMode.allCases,
                    id: \.self
                ) { mode in
                    Text(localizer[mode.menuLabel]).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(
                localizer[.preventSleepWhileAgentRunning]
            )
        }
        .frame(minHeight: 64)
        .padding(.vertical, 4)
    }

    private func integrationRow(
        _ state: AgentIntegrationSettingsState
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.provider.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.provider.title)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 5) {
                    Image(systemName: state.status.symbolName)
                    Text(state.status.title(localizer: localizer))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.status.color)

                if let errorText = state.errorText {
                    Text(localizer[errorText])
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                if state.provider == .codex, state.status == .installed {
                    Text(localizer[.codexTrustGuidance])
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.status == .needsRepair {
                Button {
                    model.repair(state.provider)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(localizer[.repairIntegration])
                .accessibilityLabel(
                    localizer.repairIntegration(state.provider.title)
                )
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { state.status != .notInstalled },
                    set: { model.setInstalled($0, for: state.provider) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .help(
                state.status == .notInstalled
                    ? localizer[.installIntegration]
                    : localizer[.removeIntegration]
            )
            .accessibilityLabel(
                localizer.providerIntegration(state.provider.title)
            )
        }
        .frame(minHeight: 64)
        .padding(.vertical, 4)
    }
}

private extension AgentProvider {
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        case .antigravity: "Gemini (Antigravity)"
        case .cursor: "Cursor"
        }
    }

    var symbolName: String {
        switch self {
        case .codex: "terminal"
        case .claudeCode: "sparkles"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .antigravity: "diamond"
        case .cursor: "cursorarrow.rays"
        }
    }
}

private extension AgentIntegrationStatus {
    func title(localizer: MyTTYLocalizer) -> String {
        switch self {
        case .notInstalled: localizer[.notInstalled]
        case .installed: localizer[.installed]
        case .needsRepair: localizer[.needsRepair]
        }
    }

    var symbolName: String {
        switch self {
        case .notInstalled: "circle"
        case .installed: "checkmark.circle.fill"
        case .needsRepair: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notInstalled: .secondary
        case .installed: .green
        case .needsRepair: .orange
        }
    }
}
