import Foundation

public enum PreferencesStoreError: Error, Equatable, Sendable {
    case invalidValue(key: String, value: String)
}

public enum MyTTYTabPlacement: String, CaseIterable, Equatable, Sendable {
    case left
    case right
    case top
    case bottom

    public var isVertical: Bool {
        switch self {
        case .left, .right:
            true
        case .top, .bottom:
            false
        }
    }
}

public enum AppLanguage: String, CaseIterable, Equatable, Sendable {
    case systemDefault = "system-default"
    case english
    case japanese
}

public enum LaunchBehavior: String, CaseIterable, Equatable, Sendable {
    case restoreLastSession = "restore-last-session"
    case newWindow = "new-window"
}

public enum CloseConfirmation: String, CaseIterable, Equatable, Sendable {
    case whenProcessRunning = "when-process-running"
    case always

    public func requiresConfirmation(
        hasRunningProcess: Bool
    ) -> Bool {
        switch self {
        case .whenProcessRunning:
            hasRunningProcess
        case .always:
            true
        }
    }
}

public enum WindowStartupBehavior: String, CaseIterable, Equatable, Sendable {
    case rememberLastSize = "remember-last-size"
    case fullscreen
    case small
}

public enum AgentSleepPreventionMode: String, CaseIterable, Equatable, Sendable {
    case allowSleep = "allow-sleep"
    case preventWhileProcessing = "prevent-while-processing"
    case preventWhileLaunched = "prevent-while-launched"
}

public struct ApplicationPreferences: Equatable, Sendable {
    public var tabPlacement: MyTTYTabPlacement
    public var keyBindings: [MyTTYCommand: MyTTYKeyBinding]
    public var language: AppLanguage
    public var launchBehavior: LaunchBehavior
    public var closeWindowConfirmation: CloseConfirmation
    public var closePaneConfirmation: CloseConfirmation
    public var closeTabConfirmation: CloseConfirmation
    public var confirmClosingLastPane: Bool
    public var windowStartupBehavior: WindowStartupBehavior
    public var showStatusBar: Bool
    public var showPressedKeyToast: Bool
    public var autocompleteEnabled: Bool
    public var agentSleepPreventionMode: AgentSleepPreventionMode
    public var attentionUnreadOnly: Bool
    public var remoteAccessEnabled: Bool
    /// Whether Attention items are pushed to paired iOS devices through
    /// APNs. Independent of `remoteAccessEnabled` only in the sense that
    /// pushes need no live connection; pairing (and therefore remote
    /// access) is still the way a device gets registered.
    public var remotePushNotificationsEnabled: Bool
    public var inactivePaneDimming: Double

    public init(
        tabPlacement: MyTTYTabPlacement = .left,
        keyBindings: [MyTTYCommand: MyTTYKeyBinding]
            = MyTTYCommand.defaultKeyBindings,
        language: AppLanguage = .systemDefault,
        launchBehavior: LaunchBehavior = .restoreLastSession,
        closeWindowConfirmation: CloseConfirmation = .whenProcessRunning,
        closePaneConfirmation: CloseConfirmation = .whenProcessRunning,
        closeTabConfirmation: CloseConfirmation = .whenProcessRunning,
        confirmClosingLastPane: Bool = true,
        windowStartupBehavior: WindowStartupBehavior = .rememberLastSize,
        showStatusBar: Bool = true,
        showPressedKeyToast: Bool = false,
        autocompleteEnabled: Bool = true,
        agentSleepPreventionMode: AgentSleepPreventionMode = .allowSleep,
        attentionUnreadOnly: Bool = false,
        remoteAccessEnabled: Bool = false,
        remotePushNotificationsEnabled: Bool = true,
        inactivePaneDimming: Double = 0.32
    ) {
        self.tabPlacement = tabPlacement
        self.keyBindings = keyBindings
        self.language = language
        self.launchBehavior = launchBehavior
        self.closeWindowConfirmation = closeWindowConfirmation
        self.closePaneConfirmation = closePaneConfirmation
        self.closeTabConfirmation = closeTabConfirmation
        self.confirmClosingLastPane = confirmClosingLastPane
        self.windowStartupBehavior = windowStartupBehavior
        self.showStatusBar = showStatusBar
        self.showPressedKeyToast = showPressedKeyToast
        self.autocompleteEnabled = autocompleteEnabled
        self.agentSleepPreventionMode = agentSleepPreventionMode
        self.attentionUnreadOnly = attentionUnreadOnly
        self.remoteAccessEnabled = remoteAccessEnabled
        self.remotePushNotificationsEnabled = remotePushNotificationsEnabled
        self.inactivePaneDimming = inactivePaneDimming
    }
}

public enum TerminalCursorStyle: String, CaseIterable, Equatable, Sendable {
    case block
    case bar
    case underline
}

public enum TerminalCursorBlink: String, CaseIterable, Equatable, Sendable {
    case system
    case enabled
    case disabled
}

public enum TerminalAppearance: String, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark
}

public struct TerminalPreferences: Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var cursorStyle: TerminalCursorStyle
    public var cursorBlink: TerminalCursorBlink
    public var appearance: TerminalAppearance
    public var theme: String
    public var foregroundHex: String
    public var backgroundHex: String
    public var backgroundOpacity: Double
    public var shell: String

    public init(
        fontFamily: String = "",
        fontSize: Double = 13,
        cursorStyle: TerminalCursorStyle = .block,
        cursorBlink: TerminalCursorBlink = .system,
        appearance: TerminalAppearance = .system,
        theme: String = "",
        foregroundHex: String = "FFFFFF",
        backgroundHex: String = "282C34",
        backgroundOpacity: Double = 1,
        shell: String = ""
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.appearance = appearance
        self.theme = theme
        self.foregroundHex = foregroundHex
        self.backgroundHex = backgroundHex
        self.backgroundOpacity = backgroundOpacity
        self.shell = shell
    }
}

public struct ApplicationPreferencesStore {
    private static let marker = "# Managed by mytty Settings: application"
    private static let managedKeys = Set(
        [
            "tab-position",
            "language",
            "on-launch",
            "confirmation.close-window",
            "confirmation.close-pane",
            "confirmation.close-tab",
            "confirmation.close-last-pane",
            "window.mode",
            "show-status-bar",
            "recording.show-keys",
            "input.show-key-toast",
            "autocomplete.enabled",
            "agents.prevent-system-sleep",
            "attention.unread-only",
            "remote.access-enabled",
            "pane.inactive-dimming",
            "keybinding.toggle-attention",
        ] + MyTTYCommand.allCases.map {
            keyBindingKey(for: $0)
        }
    )

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(from url: URL) throws -> ApplicationPreferences {
        let document = try ConfigurationDocument(
            url: url,
            fileManager: fileManager
        )
        var preferences = ApplicationPreferences()
        if let value = document.lastValue(for: "tab-position") {
            guard let placement = MyTTYTabPlacement(rawValue: value) else {
                throw PreferencesStoreError.invalidValue(
                    key: "tab-position",
                    value: value
                )
            }
            preferences.tabPlacement = placement
        }
        if let value = document.lastValue(for: "language") {
            guard let language = AppLanguage(rawValue: value) else {
                throw invalid(key: "language", value: value)
            }
            preferences.language = language
        }
        if let value = document.lastValue(for: "on-launch") {
            guard let behavior = LaunchBehavior(rawValue: value) else {
                throw invalid(key: "on-launch", value: value)
            }
            preferences.launchBehavior = behavior
        }
        if let value = document.lastValue(for: "confirmation.close-window") {
            guard let confirmation = CloseConfirmation(rawValue: value) else {
                throw invalid(
                    key: "confirmation.close-window",
                    value: value
                )
            }
            preferences.closeWindowConfirmation = confirmation
        }
        if let value = document.lastValue(for: "confirmation.close-pane") {
            guard let confirmation = CloseConfirmation(rawValue: value) else {
                throw invalid(
                    key: "confirmation.close-pane",
                    value: value
                )
            }
            preferences.closePaneConfirmation = confirmation
        }
        if let value = document.lastValue(for: "confirmation.close-tab") {
            guard let confirmation = CloseConfirmation(rawValue: value) else {
                throw invalid(
                    key: "confirmation.close-tab",
                    value: value
                )
            }
            preferences.closeTabConfirmation = confirmation
        }
        if let value = document.lastValue(
            for: "confirmation.close-last-pane"
        ) {
            guard let confirm = Bool(value) else {
                throw invalid(
                    key: "confirmation.close-last-pane",
                    value: value
                )
            }
            preferences.confirmClosingLastPane = confirm
        }
        if let value = document.lastValue(for: "window.mode") {
            guard let behavior = WindowStartupBehavior(rawValue: value) else {
                throw invalid(key: "window.mode", value: value)
            }
            preferences.windowStartupBehavior = behavior
        }
        if let value = document.lastValue(for: "show-status-bar") {
            guard let showStatusBar = Bool(value) else {
                throw invalid(key: "show-status-bar", value: value)
            }
            preferences.showStatusBar = showStatusBar
        }
        if let value = document.lastValue(for: "input.show-key-toast") {
            guard let showToast = Bool(value) else {
                throw invalid(key: "input.show-key-toast", value: value)
            }
            preferences.showPressedKeyToast = showToast
        } else if let value = document.lastValue(for: "recording.show-keys") {
            guard let showToast = Bool(value) else {
                throw invalid(key: "recording.show-keys", value: value)
            }
            preferences.showPressedKeyToast = showToast
        }
        if let value = document.lastValue(for: "autocomplete.enabled") {
            guard let enabled = Bool(value) else {
                throw invalid(key: "autocomplete.enabled", value: value)
            }
            preferences.autocompleteEnabled = enabled
        }
        if let value = document.lastValue(
            for: "agents.prevent-system-sleep"
        ) {
            if let mode = AgentSleepPreventionMode(rawValue: value) {
                preferences.agentSleepPreventionMode = mode
            } else if let legacyEnabled = Bool(value) {
                // Older installs stored a bare boolean, equivalent to
                // today's "prevent while processing" mode.
                preferences.agentSleepPreventionMode = legacyEnabled
                    ? .preventWhileProcessing
                    : .allowSleep
            } else {
                throw invalid(
                    key: "agents.prevent-system-sleep",
                    value: value
                )
            }
        }
        if let value = document.lastValue(for: "attention.unread-only") {
            guard let enabled = Bool(value) else {
                throw invalid(key: "attention.unread-only", value: value)
            }
            preferences.attentionUnreadOnly = enabled
        }
        if let value = document.lastValue(for: "remote.access-enabled") {
            guard let enabled = Bool(value) else {
                throw invalid(key: "remote.access-enabled", value: value)
            }
            preferences.remoteAccessEnabled = enabled
        }
        if let value = document.lastValue(for: "remote.push-notifications") {
            guard let enabled = Bool(value) else {
                throw invalid(key: "remote.push-notifications", value: value)
            }
            preferences.remotePushNotificationsEnabled = enabled
        }
        if let value = document.lastValue(for: "pane.inactive-dimming") {
            guard let dimming = Double(value),
                  (0...1).contains(dimming),
                  dimming.isFinite
            else {
                throw invalid(key: "pane.inactive-dimming", value: value)
            }
            preferences.inactivePaneDimming = dimming
        }

        for command in MyTTYCommand.allCases {
            let key = Self.keyBindingKey(for: command)
            guard let value = document.lastValue(for: key) else { continue }
            if value == "none" {
                preferences.keyBindings.removeValue(forKey: command)
            } else if let binding = MyTTYKeyBinding(serialized: value) {
                preferences.keyBindings[command] = binding
            } else {
                throw PreferencesStoreError.invalidValue(
                    key: key,
                    value: value
                )
            }
        }
        return preferences
    }

    public func save(
        _ preferences: ApplicationPreferences,
        to url: URL
    ) throws {
        guard (0...1).contains(preferences.inactivePaneDimming),
              preferences.inactivePaneDimming.isFinite
        else {
            throw invalid(
                key: "pane.inactive-dimming",
                value: String(preferences.inactivePaneDimming)
            )
        }
        let document = try ConfigurationDocument(
            url: url,
            fileManager: fileManager
        )
        var managed = [
            "tab-position = \(quoted(preferences.tabPlacement.rawValue))",
            "language = \(quoted(preferences.language.rawValue))",
            "on-launch = \(quoted(preferences.launchBehavior.rawValue))",
            "confirmation.close-window = \(quoted(preferences.closeWindowConfirmation.rawValue))",
            "confirmation.close-pane = \(quoted(preferences.closePaneConfirmation.rawValue))",
            "confirmation.close-tab = \(quoted(preferences.closeTabConfirmation.rawValue))",
            "confirmation.close-last-pane = \(quoted(String(preferences.confirmClosingLastPane)))",
            "window.mode = \(quoted(preferences.windowStartupBehavior.rawValue))",
            "show-status-bar = \(quoted(String(preferences.showStatusBar)))",
            "input.show-key-toast = \(quoted(String(preferences.showPressedKeyToast)))",
            "autocomplete.enabled = \(quoted(String(preferences.autocompleteEnabled)))",
            "agents.prevent-system-sleep = \(quoted(preferences.agentSleepPreventionMode.rawValue))",
            "attention.unread-only = \(quoted(String(preferences.attentionUnreadOnly)))",
            "remote.access-enabled = \(quoted(String(preferences.remoteAccessEnabled)))",
            "remote.push-notifications = \(quoted(String(preferences.remotePushNotificationsEnabled)))",
            "pane.inactive-dimming = \(quoted(decimal(preferences.inactivePaneDimming)))",
        ]
        managed.append(contentsOf: MyTTYCommand.allCases.map { command in
            let value = preferences.keyBindings[command]?.serialized ?? "none"
            return "\(Self.keyBindingKey(for: command)) = \(quoted(value))"
        })
        let lines = document.replacingManagedLines(
            keys: Self.managedKeys,
            marker: Self.marker,
            with: managed
        )
        try write(lines: lines, to: url)
    }

    private static func keyBindingKey(for command: MyTTYCommand) -> String {
        "keybinding.\(command.rawValue)"
    }

    private func invalid(key: String, value: String) -> Error {
        PreferencesStoreError.invalidValue(key: key, value: value)
    }
}

public struct TerminalPreferencesStore {
    private static let shellIntegrationFeaturesKey =
        "shell-integration-features"
    private static let fontFeatureKey = "font-feature"
    /// Disables programming ligatures (e.g. `->` rendering as `→`), which
    /// misrepresent the literal bytes a terminal shows. Ghostty enables them
    /// by default for fonts that have them (JetBrains Mono, Fira Code, …).
    private static let ligatureOffFeatures = "-calt, -liga, -dlig"
    /// Appended after the user's font as an explicit fallback so Japanese
    /// glyphs (notably 「の」) resolve deterministically instead of falling
    /// through CoreText's system fallback, which can pick a mismatched
    /// font — especially around launch or display changes.
    private static let japaneseFallbackFontFamily = "Hiragino Sans"
    private static let marker = "# Managed by mytty Settings: terminal"
    private static let managedKeys = Set([
        "font-family",
        "font-size",
        "cursor-style",
        "cursor-style-blink",
        "window-theme",
        "theme",
        "foreground",
        "background",
        "background-opacity",
        "command",
    ])

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func prepareForLaunch(at url: URL) throws {
        let document = try ConfigurationDocument(
            url: url,
            fileManager: fileManager
        )
        let current = document.lastValue(
            for: Self.shellIntegrationFeaturesKey
        )
        // Disable ligatures by default, but only when the user hasn't set any
        // `font-feature` of their own — that way they can re-enable or
        // customize ligatures by writing their own font-feature line.
        let needsLigatureDefault = document.lastValue(
            for: Self.fontFeatureKey
        ) == nil
        // A single font-family means no explicit fallback: append the
        // Japanese fallback after it so 「の」 and friends don't drift to a
        // mismatched font. Two or more entries mean the user (or an
        // earlier save) already chose a fallback chain — leave it alone.
        let fontFamilies = document.values(for: "font-family")
        let needsFontFallback = fontFamilies.count == 1
            && fontFamilies[0] != Self.japaneseFallbackFontFamily

        guard !Self.shellCursorIsDisabled(in: current)
            || needsLigatureDefault
            || needsFontFallback
        else { return }

        var replacements: [String] = []
        var keys: Set<String> = []
        if !Self.shellCursorIsDisabled(in: current) {
            keys.insert(Self.shellIntegrationFeaturesKey)
            replacements.append(
                "\(Self.shellIntegrationFeaturesKey) "
                    + "= \(Self.disablingShellCursor(in: current))"
            )
        }
        if needsLigatureDefault {
            keys.insert(Self.fontFeatureKey)
            replacements.append(
                "\(Self.fontFeatureKey) = \(Self.ligatureOffFeatures)"
            )
        }

        var lines = document.replacingAssignments(
            keys: keys,
            with: replacements
        )
        if needsFontFallback {
            lines = ConfigurationDocument.inserting(
                "font-family = \(quoted(Self.japaneseFallbackFontFamily))",
                afterLastAssignmentOf: "font-family",
                in: lines
            )
        }
        try write(lines: lines, to: url)
    }

    public func load(from url: URL) throws -> TerminalPreferences {
        let document = try ConfigurationDocument(
            url: url,
            fileManager: fileManager
        )
        var preferences = TerminalPreferences()

        // Repeated font-family entries are a fallback chain in Ghostty;
        // the first one is the primary font the Settings UI edits.
        if let value = document.firstValue(for: "font-family") {
            preferences.fontFamily = value
        }
        if let value = document.lastValue(for: "font-size") {
            guard let size = Double(value), size > 0, size.isFinite else {
                throw invalid("font-size", value)
            }
            preferences.fontSize = size
        }
        if let value = document.lastValue(for: "cursor-style") {
            guard let style = TerminalCursorStyle(rawValue: value) else {
                throw invalid("cursor-style", value)
            }
            preferences.cursorStyle = style
        }
        if let value = document.lastValue(for: "cursor-style-blink") {
            switch value {
            case "true": preferences.cursorBlink = .enabled
            case "false": preferences.cursorBlink = .disabled
            case "": preferences.cursorBlink = .system
            default: throw invalid("cursor-style-blink", value)
            }
        }
        if let value = document.lastValue(for: "window-theme") {
            guard let appearance = TerminalAppearance(rawValue: value) else {
                throw invalid("window-theme", value)
            }
            preferences.appearance = appearance
        }
        if let value = document.lastValue(for: "theme") {
            preferences.theme = try normalizedTheme(value)
        }
        if let value = document.lastValue(for: "foreground") {
            preferences.foregroundHex = try normalizedHex(
                value,
                key: "foreground"
            )
        }
        if let value = document.lastValue(for: "background") {
            preferences.backgroundHex = try normalizedHex(
                value,
                key: "background"
            )
        }
        if let value = document.lastValue(for: "background-opacity") {
            guard let opacity = Double(value),
                  (0...1).contains(opacity),
                  opacity.isFinite
            else { throw invalid("background-opacity", value) }
            preferences.backgroundOpacity = opacity
        }
        if let value = document.lastValue(for: "command") {
            preferences.shell = value
        }

        return preferences
    }

    public func save(_ preferences: TerminalPreferences, to url: URL) throws {
        guard preferences.fontSize > 0, preferences.fontSize.isFinite else {
            throw invalid("font-size", String(preferences.fontSize))
        }
        guard (0...1).contains(preferences.backgroundOpacity),
              preferences.backgroundOpacity.isFinite
        else {
            throw invalid(
                "background-opacity",
                String(preferences.backgroundOpacity)
            )
        }
        let theme = try normalizedTheme(preferences.theme)

        var managed: [String] = []
        if !preferences.fontFamily.isEmpty {
            managed.append("font-family = \(quoted(preferences.fontFamily))")
            if preferences.fontFamily != Self.japaneseFallbackFontFamily {
                managed.append(
                    "font-family = "
                        + quoted(Self.japaneseFallbackFontFamily)
                )
            }
        }
        managed.append("font-size = \(decimal(preferences.fontSize))")
        managed.append("cursor-style = \(preferences.cursorStyle.rawValue)")
        switch preferences.cursorBlink {
        case .system:
            break
        case .enabled:
            managed.append("cursor-style-blink = true")
        case .disabled:
            managed.append("cursor-style-blink = false")
        }
        managed.append("window-theme = \(preferences.appearance.rawValue)")
        if theme.isEmpty {
            let foreground = try normalizedHex(
                preferences.foregroundHex,
                key: "foreground"
            )
            let background = try normalizedHex(
                preferences.backgroundHex,
                key: "background"
            )
            managed.append("foreground = \(foreground)")
            managed.append("background = \(background)")
        } else {
            managed.append("theme = \(theme)")
        }
        managed.append(
            "background-opacity = \(decimal(preferences.backgroundOpacity))"
        )
        if !preferences.shell.isEmpty {
            managed.append("command = \(quoted(preferences.shell))")
        }

        let document = try ConfigurationDocument(
            url: url,
            fileManager: fileManager
        )
        let lines = document.replacingManagedLines(
            keys: Self.managedKeys,
            marker: Self.marker,
            with: managed
        )
        try write(lines: lines, to: url)
    }

    private func invalid(_ key: String, _ value: String) -> Error {
        PreferencesStoreError.invalidValue(key: key, value: value)
    }

    private static func shellCursorIsDisabled(in value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed == "false" { return true }
        if trimmed == "true" || trimmed.isEmpty { return false }

        var enabled = true
        for feature in trimmed.split(separator: ",") {
            switch feature.trimmingCharacters(in: .whitespaces) {
            case "cursor": enabled = true
            case "no-cursor": enabled = false
            default: continue
            }
        }
        return !enabled
    }

    private static func disablingShellCursor(in value: String?) -> String {
        guard let value else { return "no-cursor" }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "no-cursor" }
        if trimmed == "true" {
            return "no-cursor,sudo,title,ssh-env,ssh-terminfo,path"
        }

        var features = trimmed.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter {
            $0 != "cursor" && $0 != "no-cursor"
        }
        features.append("no-cursor")
        return features.joined(separator: ",")
    }

    private func normalizedHex(_ value: String, key: String) throws -> String {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6,
              hex.allSatisfy({ $0.isHexDigit })
        else { throw invalid(key, value) }
        return hex.uppercased()
    }

    private func normalizedTheme(_ value: String) throws -> String {
        let theme = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !theme.contains("\n"), !theme.contains("\r") else {
            throw invalid("theme", value)
        }
        return theme
    }
}

private struct ConfigurationDocument {
    let lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    init(url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            lines = []
            return
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        lines = contents.components(separatedBy: .newlines)
    }

    func lastValue(for key: String) -> String? {
        lines.reversed().compactMap(assignment).first(where: {
            $0.key == key
        })?.value
    }

    func firstValue(for key: String) -> String? {
        lines.compactMap(assignment).first(where: {
            $0.key == key
        })?.value
    }

    func values(for key: String) -> [String] {
        lines.compactMap(assignment)
            .filter { $0.key == key }
            .map(\.value)
    }

    /// Inserts `line` directly after the last assignment of `key`, so an
    /// appended fallback stays adjacent to the entry it extends.
    static func inserting(
        _ line: String,
        afterLastAssignmentOf key: String,
        in lines: [String]
    ) -> [String] {
        let document = ConfigurationDocument(lines: lines)
        guard let index = lines.lastIndex(where: {
            document.assignment($0)?.key == key
        }) else { return lines }
        var result = lines
        result.insert(line, at: index + 1)
        return result
    }

    func replacingManagedLines(
        keys: Set<String>,
        marker: String,
        with managedLines: [String]
    ) -> [String] {
        var preserved = lines.filter { line in
            guard line != marker else { return false }
            guard let item = assignment(line) else { return true }
            return !keys.contains(item.key)
        }
        while preserved.last?.isEmpty == true {
            preserved.removeLast()
        }
        if !preserved.isEmpty {
            preserved.append("")
        }
        preserved.append(marker)
        preserved.append(contentsOf: managedLines)
        preserved.append("")
        return preserved
    }

    func replacingAssignments(
        keys: Set<String>,
        with replacements: [String]
    ) -> [String] {
        var preserved = lines.filter { line in
            guard let item = assignment(line) else { return true }
            return !keys.contains(item.key)
        }
        while preserved.last?.isEmpty == true {
            preserved.removeLast()
        }
        preserved.append(contentsOf: replacements)
        preserved.append("")
        return preserved
    }

    private func assignment(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              let separator = trimmed.firstIndex(of: "=")
        else { return nil }
        let key = trimmed[..<separator]
            .trimmingCharacters(in: .whitespaces)
        var value = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.first == "\"", value.last == "\"" {
            value.removeFirst()
            value.removeLast()
            value = value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return (key, value)
    }
}

private func quoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func decimal(_ value: Double) -> String {
    var result = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    while result.last == "0" { result.removeLast() }
    if result.last == "." { result.removeLast() }
    return result
}

private func write(lines: [String], to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(lines.joined(separator: "\n").utf8)
        .write(to: url, options: .atomic)
}
