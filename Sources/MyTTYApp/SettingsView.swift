import AppKit
import MyTTYCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var integrations: AgentIntegrationSettingsModel
    @ObservedObject var updates: ApplicationUpdateModel
    @ObservedObject var defaultTerminal: DefaultTerminalModel
    @ObservedObject var commandLineToolInstall: CommandLineToolInstallModel
    @ObservedObject var remoteAccess: RemoteAccessSettingsModel
    @State private var selection: SettingsSection? = .general
    @State private var searchText = ""

    private var localizer: MyTTYLocalizer {
        MyTTYLocalizer(language: settings.application.language)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(localizer[.search], text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                )
                .padding(16)

                List(filteredSections, selection: $selection) { section in
                    Label(
                        localizer[section.textKey],
                        systemImage: section.systemImage
                    )
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 32)
                    .tag(section)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 238)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                if let activeSection {
                    Text(localizer[activeSection.textKey].uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                }

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 560, idealHeight: 680)
        .onChange(of: searchText) {
            guard let selection, !filteredSections.contains(selection) else {
                return
            }
            self.selection = filteredSections.first
        }
        .overlay(alignment: .bottom) {
            if let message = settings.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
    }

    private var filteredSections: [SettingsSection] {
        SettingsSection.allCases.filter {
            $0.matches(searchText, localizer: localizer)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let activeSection {
            switch activeSection {
            case .general:
                GeneralSettingsView(
                    model: settings,
                    defaultTerminal: defaultTerminal,
                    localizer: localizer
                )
            case .shell:
                ShellSettingsView(
                    model: settings,
                    localizer: localizer
                )
            case .agents:
                AgentIntegrationSettingsView(
                    settings: settings,
                    model: integrations,
                    localizer: localizer
                )
            case .orchestration:
                OrchestrationSettingsView(
                    model: integrations,
                    commandLineToolInstall: commandLineToolInstall,
                    localizer: localizer
                )
            case .keyBindings:
                KeyBindingsSettingsView(model: settings, localizer: localizer)
            case .remote:
                RemoteAccessSettingsView(
                    settings: settings,
                    model: remoteAccess,
                    localizer: localizer
                )
            case .update:
                UpdatesSettingsView(
                    model: updates,
                    localizer: localizer
                )
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text(localizer[.noMatchingSettings])
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var activeSection: SettingsSection? {
        if let selection, filteredSections.contains(selection) {
            return selection
        }
        return filteredSections.first
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shell
    case agents
    case orchestration
    case keyBindings
    case remote
    case update

    var id: Self { self }

    var textKey: MyTTYText {
        switch self {
        case .general: .general
        case .shell: .shell
        case .agents: .agents
        case .orchestration: .orchestration
        case .keyBindings: .keyBindings
        case .remote: .remote
        case .update: .update
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shell: "terminal"
        case .agents: "bell.badge"
        case .orchestration: "person.3"
        case .keyBindings: "keyboard"
        case .remote: "iphone"
        case .update: "arrow.triangle.2.circlepath"
        }
    }

    func matches(_ query: String, localizer: MyTTYLocalizer) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return true }

        let terms = [localizer[textKey], rawValue] + searchTerms
        return terms.contains { $0.lowercased().contains(query) }
    }

    private var searchTerms: [String] {
        switch self {
        case .general:
            [
                "language", "launch", "session", "tabs", "position",
                "keys", "toast", "input", "default terminal", "window",
                "size", "fullscreen", "confirmation", "close", "status",
                "bar",
            ]
        case .shell:
            [
                "terminal", "font", "color", "appearance", "theme",
                "opacity", "cursor", "shell", "autocomplete", "completion",
                "inline", "suggestion", "tab",
            ]
        case .agents:
            [
                "agents", "attention", "codex", "claude", "opencode",
                "gemini", "antigravity", "cursor", "sleep",
            ]
        case .orchestration:
            [
                "orchestration", "subagent", "sub-agent", "pane team",
                "mytty-ctl", "cli", "command line tool", "path",
                "agents.md", "claude.md", "skill", "guide", "worker",
            ]
        case .keyBindings:
            ["keybindings", "keyboard", "shortcut", "keys", "conflict"]
        case .remote:
            [
                "ios", "iphone", "ipad", "remote", "pairing", "pair",
                "bonjour", "network",
            ]
        case .update:
            ["updates", "update", "version", "release", "about"]
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var defaultTerminal: DefaultTerminalModel
    let localizer: MyTTYLocalizer
    @State private var importedReleaseSettings = false

    private static let releaseSettingsSource = ApplicationPaths(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ),
        profile: .release
    )

    var body: some View {
        Form {
            Section(localizer[.application]) {
                Picker(
                    localizer[.language],
                    selection: applicationBinding(\.language)
                ) {
                    Text(localizer[.systemDefault])
                        .tag(AppLanguage.systemDefault)
                    Text(localizer[.english]).tag(AppLanguage.english)
                    Text(localizer[.japanese]).tag(AppLanguage.japanese)
                }
                .pickerStyle(.menu)

                Picker(
                    localizer[.onLaunch],
                    selection: applicationBinding(\.launchBehavior)
                ) {
                    Text(localizer[.restoreLastSession])
                        .tag(LaunchBehavior.restoreLastSession)
                    Text(localizer[.newWindow])
                        .tag(LaunchBehavior.newWindow)
                }
                .pickerStyle(.menu)

                LabeledContent(localizer[.defaultTerminal]) {
                    if defaultTerminal.isDefault {
                        Label {
                            Text(localizer[.defaultTerminalActive])
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button(localizer[.makeDefaultTerminal]) {
                            Task {
                                await defaultTerminal.makeDefault()
                            }
                        }
                        .disabled(defaultTerminal.isUpdating)
                    }
                }

                if defaultTerminal.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else if defaultTerminal.failure != nil {
                    Text(localizer[.defaultTerminalRegistrationFailed])
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(localizer[.tabs]) {
                Picker(
                    localizer[.position],
                    selection: applicationBinding(\.tabPlacement)
                ) {
                    Label(localizer[.left], systemImage: "sidebar.left")
                        .tag(MyTTYTabPlacement.left)
                    Label(localizer[.right], systemImage: "sidebar.right")
                        .tag(MyTTYTabPlacement.right)
                    Label(
                        localizer[.top],
                        systemImage: "rectangle.topthird.inset.filled"
                    )
                        .tag(MyTTYTabPlacement.top)
                    Label(
                        localizer[.bottom],
                        systemImage: "rectangle.bottomthird.inset.filled"
                    )
                        .tag(MyTTYTabPlacement.bottom)
                }
                .pickerStyle(.segmented)

                Picker(
                    localizer[.newTabPosition],
                    selection: applicationBinding(\.newTabPosition)
                ) {
                    Text(localizer[.newTabPositionEnd])
                        .tag(NewTabPosition.end)
                    Text(localizer[.newTabPositionAfterCurrent])
                        .tag(NewTabPosition.afterCurrent)
                }
                .pickerStyle(.menu)

                Toggle(
                    localizer[.showTabUptime],
                    isOn: applicationBinding(\.showTabUptime)
                )
                .toggleStyle(.switch)
            }

            Section(localizer[.input]) {
                Toggle(
                    localizer[.showPressedKeysInPane],
                    isOn: applicationBinding(\.showPressedKeyToast)
                )
                .toggleStyle(.switch)

                Toggle(
                    localizer[.holdSplitShortcutForOuterSplit],
                    isOn: applicationBinding(\.outerSplitOnHold)
                )
                .toggleStyle(.switch)
            }

            Section(localizer[.gifRecording]) {
                Toggle(
                    localizer[.recordingCountdownEnabled],
                    isOn: applicationBinding(\.recordingCountdownEnabled)
                )
                .toggleStyle(.switch)

                Toggle(
                    localizer[.recordingFadeOutAtEnd],
                    isOn: applicationBinding(\.recordingFadeOutEnabled)
                )
                .toggleStyle(.switch)

                if model.application.recordingFadeOutEnabled {
                    ColorPicker(
                        localizer[.recordingFadeOutColor],
                        selection: applicationColorBinding(
                            \.recordingFadeOutColorHex
                        ),
                        supportsOpacity: false
                    )

                    HStack {
                        Text(localizer[.recordingFadeOutDuration])
                        Slider(
                            value: applicationBinding(
                                \.recordingFadeOutDuration
                            ),
                            in: 0.1...2,
                            step: 0.1
                        )
                        Text(
                            Measurement<UnitDuration>(
                                value: model.application
                                    .recordingFadeOutDuration,
                                unit: .seconds
                            ),
                            format: .measurement(
                                width: .narrow,
                                numberFormatStyle:
                                    .number.precision(.fractionLength(1))
                            )
                        )
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            Section(localizer[.window]) {
                Picker(
                    localizer[.mode],
                    selection: applicationBinding(\.windowStartupBehavior)
                ) {
                    Text(localizer[.rememberLastSize])
                        .tag(WindowStartupBehavior.rememberLastSize)
                    Text(localizer[.fullscreen])
                        .tag(WindowStartupBehavior.fullscreen)
                    Text(localizer[.small])
                        .tag(WindowStartupBehavior.small)
                }
                .pickerStyle(.menu)

                Toggle(
                    localizer[.statusBar],
                    isOn: applicationBinding(\.showStatusBar)
                )
                .toggleStyle(.switch)
            }

            Section(localizer[.confirmation]) {
                confirmationPicker(
                    localizer[.closeWindow],
                    keyPath: \.closeWindowConfirmation
                )
                confirmationPicker(
                    localizer[.closePane],
                    keyPath: \.closePaneConfirmation
                )
                confirmationPicker(
                    localizer[.closeTab],
                    keyPath: \.closeTabConfirmation
                )
                Toggle(
                    localizer[.closeLastPane],
                    isOn: applicationBinding(\.confirmClosingLastPane)
                )
                .toggleStyle(.switch)
            }

            if ApplicationIdentity.isDevelopmentBuild {
                Section(localizer[.development]) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(localizer[.importReleaseSettings]) {
                                importedReleaseSettings =
                                    model.importSettings(
                                        from: Self.releaseSettingsSource
                                    )
                            }
                            if importedReleaseSettings {
                                Label(
                                    localizer[.releaseSettingsImported],
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        Text(localizer[.importReleaseSettingsDescription])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func confirmationPicker(
        _ title: String,
        keyPath: WritableKeyPath<ApplicationPreferences, CloseConfirmation>
    ) -> some View {
        Picker(title, selection: applicationBinding(keyPath)) {
            Text(localizer[.whenProcessRunning])
                .tag(CloseConfirmation.whenProcessRunning)
            Text(localizer[.always]).tag(CloseConfirmation.always)
        }
        .pickerStyle(.menu)
    }

    private func applicationBinding<Value>(
        _ keyPath: WritableKeyPath<ApplicationPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.application[keyPath: keyPath] },
            set: { value in
                model.updateApplication { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func applicationColorBinding(
        _ keyPath: WritableKeyPath<ApplicationPreferences, String>
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(
                    nsColor: NSColor(
                        hexRGB: model.application[keyPath: keyPath]
                    )
                )
            },
            set: { color in
                guard let hex = NSColor(color).hexRGB else { return }
                model.updateApplication { $0[keyPath: keyPath] = hex }
            }
        )
    }
}

private struct ShellSettingsView: View {
    private static let fontMenuPointSize: CGFloat = 13

    @ObservedObject var model: SettingsModel
    let localizer: MyTTYLocalizer
    @State private var availableFontFamilies =
        NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section(localizer[.font]) {
                Picker(localizer[.family], selection: binding(\.fontFamily)) {
                    fontFamilyLabel(localizer[.systemDefault], family: "")
                        .tag("")
                    ForEach(
                        FontFamilyPresentation.menuFamilies(
                            available: availableFontFamilies,
                            selected: model.terminal.fontFamily
                        ),
                        id: \.self
                    ) { family in
                        fontFamilyLabel(
                            FontFamilyPresentation.displayName(
                                for: family,
                                language: localizer.language
                            ),
                            family: family
                        )
                            .tag(family)
                    }
                }

                HStack {
                    Text(localizer[.size])
                    Spacer()
                    TextField(
                        localizer[.size],
                        value: binding(\.fontSize),
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .labelsHidden()
                    .accessibilityLabel(localizer[.size])
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    Stepper(
                        "",
                        value: binding(\.fontSize),
                        in: 6...72,
                        step: 0.5
                    )
                    .labelsHidden()
                }
            }

            Section(localizer[.appearance]) {
                Picker(localizer[.mode], selection: binding(\.appearance)) {
                    Text(localizer[.system]).tag(TerminalAppearance.system)
                    Text(localizer[.light]).tag(TerminalAppearance.light)
                    Text(localizer[.dark]).tag(TerminalAppearance.dark)
                }
                .pickerStyle(.segmented)

                GhosttyThemePicker(
                    selection: binding(\.theme),
                    catalog: model.terminalThemes,
                    customBackgroundHex: model.terminal.backgroundHex,
                    customForegroundHex: model.terminal.foregroundHex,
                    localizer: localizer
                )

                if model.terminal.theme.isEmpty {
                    ColorPicker(
                        localizer[.text],
                        selection: colorBinding(\.foregroundHex),
                        supportsOpacity: false
                    )
                    ColorPicker(
                        localizer[.background],
                        selection: colorBinding(\.backgroundHex),
                        supportsOpacity: false
                    )
                }

                HStack {
                    Text(localizer[.backgroundOpacity])
                    Slider(
                        value: binding(\.backgroundOpacity),
                        in: 0.2...1,
                        step: 0.05
                    )
                    Text(model.terminal.backgroundOpacity, format: .percent)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }

                HStack {
                    Text(localizer[.inactivePaneDimming])
                    Slider(
                        value: applicationBinding(\.inactivePaneDimming),
                        in: 0...0.8,
                        step: 0.05
                    )
                    Text(
                        model.application.inactivePaneDimming,
                        format: .percent
                    )
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
                }

                Toggle(
                    localizer[.activePaneBorder],
                    isOn: applicationBinding(\.activePaneBorderEnabled)
                )
                .toggleStyle(.switch)

                if model.application.activePaneBorderEnabled {
                    ColorPicker(
                        localizer[.activePaneBorderColor],
                        selection: applicationAccentColorBinding(
                            \.activePaneBorderColorHex
                        ),
                        supportsOpacity: false
                    )

                    HStack {
                        Text(localizer[.activePaneBorderWidth])
                        Slider(
                            value: applicationBinding(\.activePaneBorderWidth),
                            in: 1...6,
                            step: 0.5
                        )
                        Text(
                            model.application.activePaneBorderWidth,
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            Section(localizer[.cursor]) {
                Picker(localizer[.shape], selection: binding(\.cursorStyle)) {
                    Text(localizer[.block]).tag(TerminalCursorStyle.block)
                    Text(localizer[.bar]).tag(TerminalCursorStyle.bar)
                    Text(localizer[.underline])
                        .tag(TerminalCursorStyle.underline)
                }
                .pickerStyle(.segmented)

                Picker(localizer[.blink], selection: binding(\.cursorBlink)) {
                    Text(localizer[.terminalDefault])
                        .tag(TerminalCursorBlink.system)
                    Text(localizer[.on]).tag(TerminalCursorBlink.enabled)
                    Text(localizer[.off]).tag(TerminalCursorBlink.disabled)
                }
            }

            Section(localizer[.shell]) {
                TextField(
                    localizer[.defaultLoginShell],
                    text: binding(\.shell)
                )
            }

            Section(localizer[.autocomplete]) {
                Toggle(
                    localizer[.inlineSuggestions],
                    isOn: applicationBinding(\.autocompleteEnabled)
                )
                .toggleStyle(.switch)

                LabeledContent(localizer[.acceptSuggestion]) {
                    Text(localizer[.tabKey])
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onReceive(NotificationCenter.default.publisher(
            for: kCTFontManagerRegisteredFontsChangedNotification
                as NSNotification.Name
        ).receive(on: DispatchQueue.main)) { _ in
            availableFontFamilies =
                NSFontManager.shared.availableFontFamilies
        }
    }

    private func fontFamilyLabel(_ title: String, family: String) -> Text {
        Text(title).font(Font(FontFamilyPresentation.font(
            for: family,
            size: Self.fontMenuPointSize
        )))
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<TerminalPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.terminal[keyPath: keyPath] },
            set: { value in
                model.updateTerminal { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func applicationBinding<Value>(
        _ keyPath: WritableKeyPath<ApplicationPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.application[keyPath: keyPath] },
            set: { value in
                model.updateApplication { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func colorBinding(
        _ keyPath: WritableKeyPath<TerminalPreferences, String>
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(hexRGB: model.terminal[keyPath: keyPath]))
            },
            set: { color in
                guard let hex = NSColor(color).hexRGB else { return }
                model.updateTerminal { $0[keyPath: keyPath] = hex }
            }
        )
    }

    /// Same as `colorBinding`, for application preferences whose empty
    /// string means "follow the system accent color".
    private func applicationAccentColorBinding(
        _ keyPath: WritableKeyPath<ApplicationPreferences, String>
    ) -> Binding<Color> {
        Binding(
            get: {
                let hex = model.application[keyPath: keyPath]
                return Color(
                    nsColor: hex.isEmpty
                        ? .controlAccentColor
                        : NSColor(hexRGB: hex)
                )
            },
            set: { color in
                guard let hex = NSColor(color).hexRGB else { return }
                model.updateApplication { $0[keyPath: keyPath] = hex }
            }
        )
    }
}

private struct KeyBindingsSettingsView: View {
    @ObservedObject var model: SettingsModel
    let localizer: MyTTYLocalizer

    var body: some View {
        List {
            ForEach(KeyBindingSettingsCatalog.groups, id: \.title) { group in
                keyBindingSection(
                    localizer[group.title],
                    commands: group.commands
                )
            }
        }
        .listStyle(.inset)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func keyBindingSection(
        _ title: String,
        commands: [MyTTYCommand]
    ) -> some View {
        Section(title) {
            ForEach(commands, id: \.self) { command in
                KeyBindingRow(
                    command: command,
                    model: model,
                    localizer: localizer
                )
            }
        }
    }
}

private struct KeyBindingRow: View {
    let command: MyTTYCommand
    @ObservedObject var model: SettingsModel
    let localizer: MyTTYLocalizer

    private var conflicts: [MyTTYCommand] {
        MyTTYKeyBindingConflicts.commands(
            conflictingWith: command,
            in: model.application.keyBindings
        )
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                KeyBindingRecorder(
                    command: command,
                    binding: model.application.keyBindings[command],
                    localizer: localizer,
                    onChange: { binding in
                        model.setKeyBinding(binding, for: command)
                    }
                )
                .frame(width: 132, height: 24)

                Button {
                    model.setKeyBinding(
                        MyTTYCommand.defaultKeyBindings[command],
                        for: command
                    )
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(localizer[.restoreDefault])
                .disabled(
                    model.application.keyBindings[command]
                        == MyTTYCommand.defaultKeyBindings[command]
                )
            }
        } label: {
            HStack(spacing: 6) {
                Text(localizer.commandTitle(command))
                if !conflicts.isEmpty {
                    Label(
                        localizer.conflicts(
                            with: conflicts.map(localizer.commandTitle)
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(
                        localizer.conflicts(
                            with: conflicts.map(localizer.commandTitle)
                        )
                    )
                }
            }
        }
    }
}

private struct KeyBindingRecorder: NSViewRepresentable {
    let command: MyTTYCommand
    let binding: MyTTYKeyBinding?
    let localizer: MyTTYLocalizer
    let onChange: (MyTTYKeyBinding?) -> Void

    func makeNSView(context: Context) -> KeyBindingRecorderButton {
        let button = KeyBindingRecorderButton(
            binding: binding,
            notSetTitle: localizer[.notSet],
            recordingTitle: localizer[.recording],
            onChange: onChange
        )
        let title = localizer.commandTitle(command)
        button.toolTip = localizer.keyBindingLabel(for: title)
        button.setAccessibilityLabel(
            localizer.keyBindingLabel(for: title)
        )
        return button
    }

    func updateNSView(
        _ button: KeyBindingRecorderButton,
        context: Context
    ) {
        button.updateTitles(
            notSetTitle: localizer[.notSet],
            recordingTitle: localizer[.recording]
        )
        button.setBinding(binding)
        let title = localizer.commandTitle(command)
        button.toolTip = localizer.keyBindingLabel(for: title)
        button.setAccessibilityLabel(
            localizer.keyBindingLabel(for: title)
        )
    }
}

