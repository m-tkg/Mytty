import AppKit
import SwiftUI

enum GhosttyThemeGalleryModel {
    static func options(
        currentTheme: String,
        catalog: [GhosttyThemePreview]
    ) -> [GhosttyThemePreview] {
        guard !currentTheme.isEmpty,
              !catalog.contains(where: { $0.name == currentTheme })
        else { return catalog }
        return [GhosttyThemePreview(
            name: currentTheme,
            backgroundHex: GhosttyThemePreview.fallbackBackgroundHex,
            foregroundHex: GhosttyThemePreview.fallbackForegroundHex
        )] + catalog
    }

    static func filtered(
        _ themes: [GhosttyThemePreview],
        query: String
    ) -> [GhosttyThemePreview] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return themes }
        return themes.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }
}

struct GhosttyThemePicker: View {
    @Binding var selection: String
    let catalog: [GhosttyThemePreview]
    let customBackgroundHex: String
    let customForegroundHex: String
    let localizer: MyTTYLocalizer

    @State private var isGalleryPresented = false

    var body: some View {
        LabeledContent(localizer[.theme]) {
            Button {
                isGalleryPresented = true
            } label: {
                HStack(spacing: 10) {
                    GhosttyThemePreviewCanvas(theme: selectedPreview)
                        .frame(width: 74, height: 42)
                    Text(selectedTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(width: 310, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizer[.theme])
            .accessibilityValue(selectedTitle)
            .sheet(isPresented: $isGalleryPresented) {
                GhosttyThemeGallery(
                    selection: $selection,
                    themes: availableThemes,
                    customTheme: customPreview,
                    localizer: localizer
                )
            }
        }
    }

    private var availableThemes: [GhosttyThemePreview] {
        GhosttyThemeGalleryModel.options(
            currentTheme: selection,
            catalog: catalog
        )
    }

    private var customPreview: GhosttyThemePreview {
        GhosttyThemePreview(
            name: localizer[.customColors],
            backgroundHex: customBackgroundHex,
            foregroundHex: customForegroundHex
        )
    }

    private var selectedPreview: GhosttyThemePreview {
        guard !selection.isEmpty else { return customPreview }
        return availableThemes.first(where: { $0.name == selection })
            ?? GhosttyThemePreview(
                name: selection,
                backgroundHex: GhosttyThemePreview.fallbackBackgroundHex,
                foregroundHex: GhosttyThemePreview.fallbackForegroundHex
            )
    }

    private var selectedTitle: String {
        selection.isEmpty ? localizer[.customColors] : selection
    }
}

private struct GhosttyThemeGallery: View {
    private static let customThemeID = "mytty.custom-theme"

    @Binding var selection: String
    let themes: [GhosttyThemePreview]
    let customTheme: GhosttyThemePreview
    let localizer: MyTTYLocalizer

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localizer[.theme])
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(localizer[.done]) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(localizer[.search], text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        if showsCustomTheme {
                            themeButton(
                                customTheme,
                                value: "",
                                id: Self.customThemeID
                            )
                        }
                        ForEach(filteredThemes) { theme in
                            themeButton(theme, value: theme.name, id: theme.id)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    let selectedID = selection.isEmpty
                        ? Self.customThemeID
                        : selection
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 500, idealHeight: 600)
    }

    private var filteredThemes: [GhosttyThemePreview] {
        GhosttyThemeGalleryModel.filtered(themes, query: query)
    }

    private var showsCustomTheme: Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            || customTheme.name.localizedCaseInsensitiveContains(query)
    }

    private func themeButton(
        _ theme: GhosttyThemePreview,
        value: String,
        id: String
    ) -> some View {
        Button {
            selection = value
        } label: {
            GhosttyThemeCard(theme: theme, isSelected: selection == value)
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

private struct GhosttyThemeCard: View {
    let theme: GhosttyThemePreview
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GhosttyThemePreviewCanvas(theme: theme)
                .frame(height: 78)

            HStack(spacing: 6) {
                Text(theme.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected
                        ? Color.accentColor
                        : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(Rectangle())
    }
}

private struct GhosttyThemePreviewCanvas: View {
    let theme: GhosttyThemePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(swatch(1)).frame(width: 5, height: 5)
                Circle().fill(swatch(3)).frame(width: 5, height: 5)
                Circle().fill(swatch(2)).frame(width: 5, height: 5)
            }

            HStack(spacing: 4) {
                Text("~")
                    .foregroundStyle(swatch(4))
                Text("$ git status")
                    .foregroundStyle(foreground)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .lineLimit(1)

            HStack(spacing: 3) {
                ForEach(Array(swatchColors.prefix(8).enumerated()), id: \.offset) {
                    _, color in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(foreground.opacity(0.18))
        }
    }

    private var background: Color { color(theme.backgroundHex) }
    private var foreground: Color { color(theme.foregroundHex) }

    private var swatchColors: [Color] {
        let colors = theme.paletteHex.map(color)
        return colors.isEmpty ? [foreground] : colors
    }

    private func swatch(_ index: Int) -> Color {
        guard !swatchColors.isEmpty else { return foreground }
        return swatchColors[index % swatchColors.count]
    }

    private func color(_ hex: String) -> Color {
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            return Color(nsColor: .textColor)
        }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
