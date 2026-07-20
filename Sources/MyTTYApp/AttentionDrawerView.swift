import AppKit
import MyTTYCore
import SwiftUI

enum AttentionFocusControlPresentation {
    static let symbolName = "return"
}

struct AttentionDrawerView: View {
    @ObservedObject var center: AttentionCenter
    let localizer: MyTTYLocalizer
    let showsUnreadOnly: Bool
    let onClose: () -> Void
    let onFocus: (AttentionItem) -> Void
    let onAcknowledge: (AttentionItem) -> Void
    let onAcknowledgeAll: () -> Void

    private var visibleItems: [AttentionItem] {
        showsUnreadOnly ? center.items.filter(\.isActionable) : center.items
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            itemRow(item)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
            Text(localizer[.attention])
                .font(.headline)
            if center.actionableCount > 0 {
                Text("\(center.actionableCount)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .accessibilityLabel(
                        localizer.attentionCount(center.actionableCount)
                    )
            }
            Spacer(minLength: 8)
            if center.actionableCount > 0 {
                Button(action: onAcknowledgeAll) {
                    Image(systemName: "checkmark.circle")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(localizer[.clearAllAttention])
                .accessibilityLabel(localizer[.clearAllAttention])
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(localizer[.closeAttention])
            .accessibilityLabel(localizer[.closeAttention])
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(localizer[.noItemsNeedAttention])
                .font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func itemRow(_ item: AttentionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.kind.symbolName)
                    .foregroundStyle(item.isActionable ? item.kind.color : .secondary)
                    .frame(width: 18)
                Text(item.kind.title(localizer: localizer))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Text(item.createdAt, style: .relative)
                    Text(localizer[.ago])
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(
                item.message
                    ?? item.kind.fallbackMessage(localizer: localizer)
            )
                .font(.system(size: 12))
                .foregroundStyle(item.isActionable ? .primary : .secondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                Text(item.provider.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.isActionable {
                    Text(localizer[.resolved])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    onFocus(item)
                } label: {
                    Image(
                        systemName: AttentionFocusControlPresentation.symbolName
                    )
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(localizer[.moveToShell])
                .accessibilityLabel(localizer[.moveToShell])
                .pointingHandOnHover()

                if item.isActionable {
                    Button {
                        onAcknowledge(item)
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(localizer[.acknowledge])
                    .accessibilityLabel(localizer[.acknowledge])
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func pointingHandOnHover() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

private extension AttentionItemKind {
    func title(localizer: MyTTYLocalizer) -> String {
        switch self {
        case .approvalRequest: localizer[.approvalRequested]
        case .inputRequest: localizer[.inputRequested]
        case .failure: localizer[.agentFailed]
        case .disconnected: localizer[.agentDisconnected]
        case .completion: localizer[.workCompleted]
        }
    }

    func fallbackMessage(localizer: MyTTYLocalizer) -> String {
        switch self {
        case .approvalRequest: localizer[.approvalFallback]
        case .inputRequest: localizer[.inputFallback]
        case .failure: localizer[.failureFallback]
        case .disconnected: localizer[.disconnectedFallback]
        case .completion: localizer[.completionFallback]
        }
    }

    var symbolName: String {
        switch self {
        case .approvalRequest: "checkmark.shield"
        case .inputRequest: "text.cursor"
        case .failure: "exclamationmark.triangle"
        case .disconnected: "bolt.slash"
        case .completion: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .approvalRequest: .orange
        case .inputRequest: .blue
        case .failure,
             .disconnected: .red
        case .completion: .green
        }
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
}
