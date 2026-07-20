import AppKit
import MyTTYCore

/// One executable command palette row: a leaf item of the main menu,
/// described by its localized title, its menu path, and its shortcut.
struct CommandPaletteEntry: Equatable {
    let title: String
    /// The submenu chain the item lives under, e.g. "Pane ▸ Resize".
    let path: String
    /// Human-readable key equivalent (e.g. "⇧⌘P"), empty when unbound.
    let shortcut: String
}

/// Pure filtering/ranking over palette entries so the search behavior is
/// testable without AppKit. Every whitespace-separated query token must
/// match the title or the path; titles rank prefix > word prefix >
/// substring > subsequence, and title matches beat path-only matches.
enum CommandPaletteSearch {
    static func filter(
        _ entries: [CommandPaletteEntry],
        query: String
    ) -> [CommandPaletteEntry] {
        let tokens = query.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return entries }

        let scored: [(entry: CommandPaletteEntry, score: Int, index: Int)] =
            entries.enumerated().compactMap { index, entry in
                guard let score = score(entry, tokens: tokens)
                else { return nil }
                return (entry, score, index)
            }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.entry.title.count != $1.entry.title.count {
                    return $0.entry.title.count < $1.entry.title.count
                }
                return $0.index < $1.index
            }
            .map(\.entry)
    }

    private static func score(
        _ entry: CommandPaletteEntry,
        tokens: [String]
    ) -> Int? {
        let title = entry.title.lowercased()
        let path = entry.path.lowercased()
        var total = 0
        for token in tokens {
            if title.hasPrefix(token) {
                total += 400
            } else if title.split(whereSeparator: \.isWhitespace)
                .contains(where: { $0.hasPrefix(token) }) {
                total += 300
            } else if title.contains(token) {
                total += 200
            } else if isSubsequence(token, of: title) {
                total += 100
            } else if path.contains(token) {
                total += 50
            } else if isSubsequence(token, of: path) {
                total += 25
            } else {
                return nil
            }
        }
        return total
    }

    private static func isSubsequence(
        _ needle: String,
        of haystack: String
    ) -> Bool {
        var remaining = Substring(needle)
        for character in haystack {
            if character == remaining.first {
                remaining = remaining.dropFirst()
                if remaining.isEmpty { return true }
            }
        }
        return remaining.isEmpty
    }
}

/// Flattens the main menu into palette entries paired with their live
/// `NSMenuItem`s, so executing a row dispatches exactly what the menu
/// would (same action, target, and responder-chain routing).
@MainActor
enum CommandPaletteMenuCollector {
    static func commands(
        in menu: NSMenu,
        excluding excludedAction: Selector? = nil
    ) -> [(entry: CommandPaletteEntry, item: NSMenuItem)] {
        collect(menu: menu, path: [], excluding: excludedAction)
    }

    private static func collect(
        menu: NSMenu,
        path: [String],
        excluding excludedAction: Selector?
    ) -> [(entry: CommandPaletteEntry, item: NSMenuItem)] {
        var result: [(CommandPaletteEntry, NSMenuItem)] = []
        for item in menu.items {
            guard !item.isSeparatorItem, !item.isHidden, !item.isAlternate
            else { continue }
            if let submenu = item.submenu {
                result.append(contentsOf: collect(
                    menu: submenu,
                    path: path + [submenu.title],
                    excluding: excludedAction
                ))
                continue
            }
            guard let action = item.action, action != excludedAction,
                  !item.title.isEmpty
            else { continue }
            result.append((
                CommandPaletteEntry(
                    title: item.title,
                    path: path.joined(separator: " ▸ "),
                    shortcut: shortcutDescription(of: item)
                ),
                item
            ))
        }
        return result
    }

    static func shortcutDescription(of item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return "" }
        var symbols = ""
        let mask = item.keyEquivalentModifierMask
        if mask.contains(.control) { symbols += "⌃" }
        if mask.contains(.option) { symbols += "⌥" }
        if mask.contains(.shift) { symbols += "⇧" }
        if mask.contains(.command) { symbols += "⌘" }
        return symbols + keyName(key)
    }

    private static func keyName(_ key: String) -> String {
        switch key {
        case "\r": return "↩"
        case "\t": return "⇥"
        case " ": return "Space"
        case "\u{1b}": return "Esc"
        case "\u{7f}", "\u{8}": return "⌫"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): return "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): return "↓"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): return "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): return "→"
        default: return key.uppercased()
        }
    }
}
