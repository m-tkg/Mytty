import Foundation

public enum MyTTYCommand: String, CaseIterable, Sendable {
    case settings
    case quit
    case newWindow = "new-window"
    case openHTML = "open-html"
    case newTab = "new-tab"
    case renameTab = "rename-tab"
    case closeTab = "close-tab"
    case reopenClosed = "reopen-closed"
    case splitLeft = "split-left"
    case splitRight = "split-right"
    case splitUp = "split-up"
    case splitDown = "split-down"
    case focusLeft = "focus-left"
    case focusRight = "focus-right"
    case focusUp = "focus-up"
    case focusDown = "focus-down"
    case equalizePanes = "equalize-panes"
    case togglePaneZoom = "toggle-pane-zoom"
    case swapPanes = "swap-panes"
    case findInPane = "find-in-pane"
    case showPaneList = "show-pane-list"
    case closePane = "close-pane"
    case toggleTabPanel = "toggle-tab-panel"
    case toggleRecording = "toggle-recording"
    case commandPalette = "command-palette"
    /// macOS 26+ only: explains the focused pane with the on-device model.
    case explainPane = "explain-pane"
    /// macOS 26+ only: composes a shell one-liner from natural language
    /// with the on-device model.
    case composeOneLiner = "compose-one-liner"
    /// macOS 26+ only: summarizes the last command's result in detail
    /// with the on-device model.
    case summarizeLastCommand = "summarize-last-command"

    public var title: String {
        switch self {
        case .settings: "Settings"
        case .quit: "Quit Mytty"
        case .newWindow: "New Window"
        case .openHTML: "Open HTML File"
        case .newTab: "New Tab"
        case .renameTab: "Rename Tab"
        case .closeTab: "Close Tab"
        case .reopenClosed: "Reopen Closed Item"
        case .splitLeft: "Split Left"
        case .splitRight: "Split Right"
        case .splitUp: "Split Up"
        case .splitDown: "Split Down"
        case .focusLeft: "Focus Left"
        case .focusRight: "Focus Right"
        case .focusUp: "Focus Up"
        case .focusDown: "Focus Down"
        case .equalizePanes: "Equalize Panes"
        case .togglePaneZoom: "Toggle Pane Zoom"
        case .swapPanes: "Swap Panes"
        case .findInPane: "Find in Pane"
        case .showPaneList: "Show All Panes"
        case .closePane: "Close Pane"
        case .toggleTabPanel: "Toggle Tab Panels"
        case .toggleRecording: "Start/Stop Recording"
        case .commandPalette: "Command Palette"
        case .explainPane: "Explain Pane"
        case .composeOneLiner: "Compose One-Liner"
        case .summarizeLastCommand: "Summarize Last Command"
        }
    }

    public static var defaultKeyBindings: [Self: MyTTYKeyBinding] {
        [
            .settings: .init(key: "comma", modifiers: [.command]),
            .quit: .init(key: "q", modifiers: [.command]),
            .newWindow: .init(key: "n", modifiers: [.command]),
            .openHTML: .init(key: "o", modifiers: [.command]),
            .newTab: .init(key: "t", modifiers: [.command]),
            .renameTab: .init(key: "r", modifiers: [.command]),
            .closeTab: .init(key: "w", modifiers: [.command]),
            .reopenClosed: .init(key: "t", modifiers: [.command, .shift]),
            .splitRight: .init(key: "d", modifiers: [.command]),
            .splitDown: .init(key: "d", modifiers: [.command, .shift]),
            .focusLeft: .init(key: "left", modifiers: [.command, .option]),
            .focusRight: .init(key: "right", modifiers: [.command, .option]),
            .focusUp: .init(key: "up", modifiers: [.command, .option]),
            .focusDown: .init(key: "down", modifiers: [.command, .option]),
            .equalizePanes: .init(
                key: "equal",
                modifiers: [.control, .command]
            ),
            .togglePaneZoom: .init(
                key: "return",
                modifiers: [.control, .command]
            ),
            .swapPanes: .init(
                key: "s",
                modifiers: [.control, .command]
            ),
            .findInPane: .init(key: "f", modifiers: [.control]),
            .showPaneList: .init(
                key: "p",
                modifiers: [.control, .command]
            ),
            .closePane: .init(key: "w", modifiers: [.command, .shift]),
            .toggleTabPanel: .init(key: "b", modifiers: [.command]),
            .toggleRecording: .init(
                key: "g",
                modifiers: [.command, .shift]
            ),
            .commandPalette: .init(
                key: "p",
                modifiers: [.command, .shift]
            ),
            .explainPane: .init(
                key: "i",
                modifiers: [.control, .command]
            ),
            .composeOneLiner: .init(
                key: "k",
                modifiers: [.control, .command]
            ),
            .summarizeLastCommand: .init(
                key: "j",
                modifiers: [.control, .command]
            ),
        ]
    }
}

public enum MyTTYKeyModifier: String, CaseIterable, Hashable, Sendable {
    case control
    case option
    case shift
    case command

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
}

public struct MyTTYKeyBinding: Equatable, Hashable, Sendable {
    public let key: String
    public let modifiers: Set<MyTTYKeyModifier>

    public init(key: String, modifiers: Set<MyTTYKeyModifier>) {
        let normalizedKey = Self.normalize(key)
        self.key = Self.shiftedPunctuationBases[normalizedKey]
            ?? normalizedKey
        self.modifiers = modifiers
    }

    public init?(serialized: String) {
        let components = serialized
            .lowercased()
            .split(separator: "+", omittingEmptySubsequences: false)
            .map(String.init)
        guard let key = components.last,
              !key.isEmpty,
              Self.isSupported(key)
        else { return nil }

        var modifiers = Set<MyTTYKeyModifier>()
        for component in components.dropLast() {
            guard let modifier = MyTTYKeyModifier(rawValue: component),
                  modifiers.insert(modifier).inserted
            else { return nil }
        }
        self.init(key: key, modifiers: modifiers)
    }

    public var serialized: String {
        (Self.modifierOrder.filter(modifiers.contains).map(\.rawValue) + [key])
            .joined(separator: "+")
    }

    public var displayName: String {
        Self.modifierOrder
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined() + Self.keyDisplayNames[key, default: key.uppercased()]
    }

    private static let modifierOrder: [MyTTYKeyModifier] = [
        .control,
        .option,
        .shift,
        .command,
    ]

    private static let namedKeys = Set([
        "left", "right", "up", "down",
        "return", "tab", "space", "escape",
        "home", "end", "page-up", "page-down",
        "comma", "period", "slash", "semicolon", "quote",
        "left-bracket", "right-bracket", "backslash", "backtick",
        "minus", "equal", "plus",
    ])

    private static let keyDisplayNames: [String: String] = [
        "left": "←",
        "right": "→",
        "up": "↑",
        "down": "↓",
        "return": "↩",
        "tab": "⇥",
        "space": "Space",
        "escape": "Esc",
        "home": "Home",
        "end": "End",
        "page-up": "Page Up",
        "page-down": "Page Down",
        "comma": ",",
        "period": ".",
        "slash": "/",
        "semicolon": ";",
        "quote": "'",
        "left-bracket": "[",
        "right-bracket": "]",
        "backslash": "\\",
        "backtick": "`",
        "minus": "-",
        "equal": "=",
        "plus": "+",
    ]

    private static func normalize(_ key: String) -> String {
        key.lowercased()
    }

    private static let shiftedPunctuationBases: [String: String] = [
        "<": "comma",
        ">": "period",
        "?": "slash",
        ":": "semicolon",
        "\"": "quote",
        "{": "left-bracket",
        "}": "right-bracket",
        "|": "backslash",
        "~": "backtick",
        "_": "minus",
        "+": "equal",
    ]

    private static func isSupported(_ key: String) -> Bool {
        namedKeys.contains(key)
            || (key.count == 1 && key.unicodeScalars.allSatisfy {
                !$0.properties.isWhitespace
                    && $0.value >= 0x20
                    && !(0x7F...0x9F).contains($0.value)
            })
    }
}

public enum MyTTYKeyBindingConflicts {
    public static func commands(
        conflictingWith command: MyTTYCommand,
        in bindings: [MyTTYCommand: MyTTYKeyBinding]
    ) -> [MyTTYCommand] {
        guard let binding = bindings[command] else { return [] }
        return MyTTYCommand.allCases.filter {
            $0 != command && bindings[$0] == binding
        }
    }
}
