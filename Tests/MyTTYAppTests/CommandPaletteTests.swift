import AppKit
import Testing

@testable import MyTTYApp

@Suite("Command palette")
struct CommandPaletteTests {
    private func entry(
        _ title: String,
        path: String = "",
        shortcut: String = ""
    ) -> CommandPaletteEntry {
        CommandPaletteEntry(title: title, path: path, shortcut: shortcut)
    }

    @Test("an empty query keeps every entry in menu order")
    func emptyQuery() {
        let entries = [entry("New Tab"), entry("Close Tab")]
        #expect(CommandPaletteSearch.filter(entries, query: "  ") == entries)
    }

    @Test("ranks prefix over word prefix over substring over subsequence")
    func ranking() {
        let entries = [
            entry("Split Right"),        // word-prefix for "ri"
            entry("Rename Tab"),         // prefix for "ri"? no ("re") — subsequence
            entry("Toggle Recording"),   // word prefix "re"
            entry("Rich Text"),          // prefix "ri"
        ]
        let results = CommandPaletteSearch.filter(entries, query: "ri")
        #expect(results.first == entry("Rich Text"))
        #expect(results.contains(entry("Split Right")))
    }

    @Test("every token must match; titles beat path-only matches")
    func tokensAndPaths() {
        let entries = [
            entry("Close Tab", path: "File"),
            entry("Close Pane", path: "Pane"),
            entry("Equalize Panes", path: "Pane"),
        ]
        let paneToken = CommandPaletteSearch.filter(entries, query: "pane")
        // Title matches ("Close Pane", "Equalize Panes") come before the
        // path-only match ("Close Tab" under Pane? none here).
        #expect(paneToken.first?.title == "Close Pane")
        #expect(paneToken.contains(entry("Equalize Panes", path: "Pane")))

        let both = CommandPaletteSearch.filter(entries, query: "close pane")
        #expect(both.first == entry("Close Pane", path: "Pane"))

        let none = CommandPaletteSearch.filter(entries, query: "zzz close")
        #expect(none.isEmpty)
    }

    @Test("subsequence matching finds abbreviated queries")
    func subsequence() {
        let entries = [entry("Toggle Pane Zoom"), entry("New Window")]
        let results = CommandPaletteSearch.filter(entries, query: "tpz")
        #expect(results == [entry("Toggle Pane Zoom")])
    }

    @Test("collects leaf menu items with paths, skipping separators")
    @MainActor
    func collector() {
        let root = NSMenu()
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "New Tab",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "t"
        )
        fileMenu.addItem(.separator())
        let subItem = NSMenuItem()
        let subMenu = NSMenu(title: "Export")
        subMenu.addItem(
            withTitle: "As GIF",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        subItem.submenu = subMenu
        fileMenu.addItem(subItem)
        fileMenu.addItem(
            withTitle: "No Action",
            action: nil,
            keyEquivalent: ""
        )
        fileItem.submenu = fileMenu
        root.addItem(fileItem)

        let commands = CommandPaletteMenuCollector.commands(in: root)
        let entries = commands.map(\.entry)
        #expect(entries.count == 2)
        #expect(entries[0].title == "New Tab")
        #expect(entries[0].path == "File")
        #expect(entries[0].shortcut == "⌘T")
        #expect(entries[1].title == "As GIF")
        #expect(entries[1].path == "File ▸ Export")
        #expect(entries[1].shortcut.isEmpty)
    }

    @Test("excludes the palette's own menu item")
    @MainActor
    func exclusion() {
        let root = NSMenu()
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(
            withTitle: "Command Palette...",
            action: #selector(AppDelegate.showCommandPalette(_:)),
            keyEquivalent: ""
        )
        viewMenu.addItem(
            withTitle: "Toggle Tab Panels",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        viewItem.submenu = viewMenu
        root.addItem(viewItem)

        let commands = CommandPaletteMenuCollector.commands(
            in: root,
            excluding: #selector(AppDelegate.showCommandPalette(_:))
        )
        #expect(commands.map(\.entry.title) == ["Toggle Tab Panels"])
    }

    @Test("formats modifier symbols in standard order")
    @MainActor
    func shortcutFormatting() {
        let item = NSMenuItem(
            title: "X",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "p"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        #expect(
            CommandPaletteMenuCollector.shortcutDescription(of: item)
                == "⇧⌘P"
        )
        let arrow = NSMenuItem(
            title: "Y",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        )
        arrow.keyEquivalentModifierMask = [.command, .option]
        #expect(
            CommandPaletteMenuCollector.shortcutDescription(of: arrow)
                == "⌥⌘↑"
        )
    }
}
