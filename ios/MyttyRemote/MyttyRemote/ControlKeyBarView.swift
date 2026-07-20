import SwiftUI

/// Modifier keys (shift/ctrl/option/command) toggle and arm for the next
/// keystroke; every other key fires immediately when tapped, combined
/// with whatever modifiers are armed.
struct ControlKeyBarView: View {
    @Binding var activeModifiers: Set<ControlKey>
    let onSpecialKey: (ControlKey) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ControlKey.barKeys) { key in
                    ControlKeyButton(
                        key: key,
                        isActive: activeModifiers.contains(key)
                    ) {
                        handleTap(key)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func handleTap(_ key: ControlKey) {
        if key.isModifier {
            if activeModifiers.contains(key) {
                activeModifiers.remove(key)
            } else {
                activeModifiers.insert(key)
            }
        } else {
            onSpecialKey(key)
        }
    }
}

private struct ControlKeyButton: View {
    let key: ControlKey
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbolName = key.symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .medium))
                } else {
                    Text(key.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .frame(minWidth: 40, minHeight: 32)
            .padding(.horizontal, 4)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
