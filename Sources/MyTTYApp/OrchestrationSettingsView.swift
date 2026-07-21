import AppKit
import MyTTYCore
import SwiftUI

/// Settings > Orchestration. Gathers everything related to letting an
/// agent running in a Mytty pane drive `mytty-ctl` to run other agents in
/// other panes as a team: the CLI symlink (moved here from General), the
/// "teach agents about Mytty orchestration" toggle (moved here from Agents), a
/// preview of exactly what that toggle writes, and worked examples of how
/// to actually ask an agent to do this.
struct OrchestrationSettingsView: View {
    @ObservedObject var model: AgentIntegrationSettingsModel
    @ObservedObject var commandLineToolInstall: CommandLineToolInstallModel
    let localizer: MyTTYLocalizer

    @State private var isPointerPreviewExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                overviewRow

                Divider()
                    .padding(.leading, 44)

                commandLineToolRow

                Divider()
                    .padding(.leading, 44)

                pointerToggleRow
                pointerTargetsSection

                Divider()
                    .padding(.leading, 44)

                examplesRow
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
        }
        .onAppear {
            model.refresh()
            commandLineToolInstall.refresh()
        }
    }

    // MARK: - Overview

    private var overviewRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            Text(localizer[.orchestrationOverviewDescription])
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Command line tool

    private var commandLineToolRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer[.commandLineTool])
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        String(
                            format: localizer[
                                .orchestrationCommandLineToolDescriptionFormat
                            ],
                            commandLineToolInstall.linkName
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if commandLineToolInstall.isInstalled {
                    Label(
                        String(
                            format: localizer[.commandLineToolInstalled],
                            commandLineToolInstall.linkName
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                } else {
                    Button(localizer[.installCommandLineTool]) {
                        commandLineToolInstall.install()
                    }
                    .disabled(commandLineToolInstall.isUpdating)
                }
            }
            .frame(minHeight: 64)

            if commandLineToolInstall.isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 44)
            } else if let failure = commandLineToolInstall.failure {
                Text(
                    String(
                        format: failure == .conflict
                            ? localizer[.commandLineToolConflict]
                            : localizer[.commandLineToolInstallFailed],
                        commandLineToolInstall.linkName
                    )
                )
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, 44)
            } else if commandLineToolInstall.isInstalled,
                      commandLineToolInstall.pathHintNeeded {
                Text(
                    String(
                        format: localizer[.commandLineToolPathHint],
                        commandLineToolInstall.pathExportLine
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Agent guidance

    private var pointerToggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer[.teachPaneTeamPointers])
                    .font(.system(size: 13, weight: .semibold))
                Text(localizer[.teachPaneTeamPointersDescription])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { model.paneTeamPointerEnabled },
                    set: { model.setPaneTeamPointerEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(localizer[.teachPaneTeamPointers])
        }
        .frame(minHeight: 64)
        .padding(.vertical, 4)
    }

    private var pointerTargetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer[.orchestrationPointerTargetsHeading])
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(
                AgentIntegrationInstaller.paneTeamPointerProviders,
                id: \.self
            ) { provider in
                pointerTargetRow(provider)
            }

            // This disclosure never writes anything -- it only renders the
            // same string `installPaneTeamPointer` would write, sourced
            // from `AgentIntegrationInstaller.paneTeamPointerPreview` via
            // the model, so it can't drift from the real write.
            DisclosureGroup(
                localizer[.orchestrationPointerPreviewButton],
                isExpanded: $isPointerPreviewExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(
                        AgentIntegrationInstaller.paneTeamPointerProviders,
                        id: \.self
                    ) { provider in
                        pointerPreview(provider)
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.leading, 44)
        .padding(.bottom, 12)
    }

    private func pointerTargetRow(_ provider: AgentProvider) -> some View {
        let status = model.paneTeamPointerStatus(for: provider)
        return HStack(spacing: 6) {
            Text(providerPointerTitle(provider))
                .font(.system(size: 11, weight: .medium))
            Text(model.paneTeamPointerURL(for: provider)?.path ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Label(
                status.title(localizer: localizer),
                systemImage: status.symbolName
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(status.color)
        }
    }

    @ViewBuilder
    private func pointerPreview(_ provider: AgentProvider) -> some View {
        if let preview = model.paneTeamPointerPreview(for: provider) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(providerPointerTitle(provider))
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button {
                        copyToPasteboard(preview)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help(localizer[.copy])
                    .accessibilityLabel(localizer[.copy])
                }

                ScrollView {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor))
                }
            }
        }
    }

    // MARK: - Examples

    private var examplesRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                Text(localizer[.orchestrationExamplesHeading])
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                exampleRow(
                    label: localizer[
                        .orchestrationExampleGuidanceOnCLIInstalledLabel
                    ],
                    prompt: localizer[.orchestrationExamplePromptGuided],
                    isCurrent: model.paneTeamPointerEnabled
                        && commandLineToolInstall.isInstalled
                )
                exampleRow(
                    label: localizer[
                        .orchestrationExampleGuidanceOnCLINotInstalledLabel
                    ],
                    prompt: localizer[.orchestrationExamplePromptGuided],
                    isCurrent: model.paneTeamPointerEnabled
                        && !commandLineToolInstall.isInstalled
                )
                Text(localizer[.orchestrationExampleCLINote])
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                exampleRow(
                    label: localizer[.orchestrationExampleGuidanceOffLabel],
                    prompt: localizer[.orchestrationExamplePromptUnguided],
                    isCurrent: !model.paneTeamPointerEnabled
                )
            }
            .padding(.leading, 44)
        }
        .padding(.vertical, 16)
    }

    private func exampleRow(
        label: String,
        prompt: String,
        isCurrent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if isCurrent {
                    Text(localizer[.orchestrationExampleCurrentBadge])
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Text(prompt)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor))
                    }

                Button {
                    copyToPasteboard(prompt)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help(localizer[.copy])
                .accessibilityLabel(localizer[.copy])
            }
        }
    }

    private func providerPointerTitle(_ provider: AgentProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode, .antigravity, .cursor: provider.rawValue
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
