import Foundation

public enum MyTTYCommand: String, CaseIterable, Sendable {
    case settings
    case quit
    case newWindow = "new-window"
    case nextWindow = "next-window"
    case previousWindow = "previous-window"
    case openHTML = "open-html"
    case newTab = "new-tab"
    case renameTab = "rename-tab"
    case closeTab = "close-tab"
    case reopenClosed = "reopen-closed"
    case nextTab = "next-tab"
    case previousTab = "previous-tab"
    case selectTab1 = "select-tab-1"
    case selectTab2 = "select-tab-2"
    case selectTab3 = "select-tab-3"
    case selectTab4 = "select-tab-4"
    case selectTab5 = "select-tab-5"
    case selectTab6 = "select-tab-6"
    case selectTab7 = "select-tab-7"
    case selectTab8 = "select-tab-8"
    case selectTab9 = "select-tab-9"
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
    case reloadBrowser = "reload-browser"
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

    /// The tab number a `selectTabN` command jumps to, `nil` for every
    /// other command. Shared by `title`, the app's localizer, and the menu
    /// item `tag` so the number lives in one place.
    public var tabNumber: Int? {
        switch self {
        case .selectTab1: 1
        case .selectTab2: 2
        case .selectTab3: 3
        case .selectTab4: 4
        case .selectTab5: 5
        case .selectTab6: 6
        case .selectTab7: 7
        case .selectTab8: 8
        case .selectTab9: 9
        default: nil
        }
    }

    /// The pane split direction a split command maps to, `nil` for every
    /// other command. Lets the shortcut router treat the four split
    /// commands uniformly when hold-to-outer-split is enabled.
    public var splitDirection: SplitDirection? {
        switch self {
        case .splitLeft: .left
        case .splitRight: .right
        case .splitUp: .up
        case .splitDown: .down
        default: nil
        }
    }

    /// `selectTab1`...`selectTab9`, in order, for building the numbered
    /// "Go to Tab" menu items and key binding rows without repeating the
    /// nine cases at each call site.
    public static let numberedTabCommands: [MyTTYCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    public var title: String {
        switch self {
        case .settings: "Settings"
        case .quit: "Quit Mytty"
        case .newWindow: "New Window"
        case .nextWindow: "Next Window"
        case .previousWindow: "Previous Window"
        case .openHTML: "Open HTML File"
        case .newTab: "New Tab"
        case .renameTab: "Rename Tab"
        case .closeTab: "Close Tab"
        case .reopenClosed: "Reopen Closed Item"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
             .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            "Go to Tab \(tabNumber ?? 0)"
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
        case .reloadBrowser: "Reload Page"
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
            .nextWindow: .init(key: "backtick", modifiers: [.command]),
            .previousWindow: .init(
                key: "backtick",
                modifiers: [.command, .shift]
            ),
            .openHTML: .init(key: "o", modifiers: [.command]),
            .newTab: .init(key: "t", modifiers: [.command]),
            .renameTab: .init(key: "r", modifiers: [.command, .shift]),
            .closeTab: .init(key: "w", modifiers: [.command]),
            .reopenClosed: .init(key: "t", modifiers: [.command, .shift]),
            .nextTab: .init(key: "tab", modifiers: [.control]),
            .previousTab: .init(key: "tab", modifiers: [.control, .shift]),
            .selectTab1: .init(key: "1", modifiers: [.command]),
            .selectTab2: .init(key: "2", modifiers: [.command]),
            .selectTab3: .init(key: "3", modifiers: [.command]),
            .selectTab4: .init(key: "4", modifiers: [.command]),
            .selectTab5: .init(key: "5", modifiers: [.command]),
            .selectTab6: .init(key: "6", modifiers: [.command]),
            .selectTab7: .init(key: "7", modifiers: [.command]),
            .selectTab8: .init(key: "8", modifiers: [.command]),
            .selectTab9: .init(key: "9", modifiers: [.command]),
            .splitLeft: .init(
                key: "backslash",
                modifiers: [.control, .shift, .command]
            ),
            .splitRight: .init(
                key: "backslash",
                modifiers: [.control, .command]
            ),
            .splitUp: .init(
                key: "minus",
                modifiers: [.control, .shift, .command]
            ),
            .splitDown: .init(key: "minus", modifiers: [.control, .command]),
            .focusLeft: .init(key: "left", modifiers: [.control, .command]),
            .focusRight: .init(key: "right", modifiers: [.control, .command]),
            .focusUp: .init(key: "up", modifiers: [.control, .command]),
            .focusDown: .init(key: "down", modifiers: [.control, .command]),
            .equalizePanes: .init(
                key: "e",
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
            .reloadBrowser: .init(key: "r", modifiers: [.control]),
            .showPaneList: .init(
                key: "a",
                modifiers: [.control, .command]
            ),
            .closePane: .init(key: "w", modifiers: [.control, .command]),
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
