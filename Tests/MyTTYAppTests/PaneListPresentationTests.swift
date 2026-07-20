import AppKit
import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Pane list presentation")
struct PaneListPresentationTests {
    @Test("lists terminal and browser panes with their current context")
    func items() throws {
        let windowID = WindowID()
        let terminal = TerminalSurfaceState(
            workingDirectory: URL(
                fileURLWithPath: "/Users/example/project",
                isDirectory: true
            )
        )
        let browser = BrowserPaneState(
            url: URL(string: "https://example.com/docs")!
        )
        var firstTab = TabSession(
            initialSurface: terminal,
            pinnedTitle: "Project"
        )
        try firstTab.split(browser: browser, direction: .right)

        let secondTerminal = TerminalSurfaceState(
            workingDirectory: URL(
                fileURLWithPath: "/Users/example/notes",
                isDirectory: true
            )
        )
        let secondTab = TabSession(
            initialSurface: secondTerminal,
            pinnedTitle: "Notes"
        )
        let session = WindowSession(
            id: windowID,
            frame: WindowFrame(x: 0, y: 0, width: 900, height: 600),
            tabs: [firstTab, secondTab],
            selectedTabID: firstTab.id
        )

        let items = PaneListPresentation.items(
            snapshots: [
                PaneListWindowSnapshot(
                    session: session,
                    commandsByPane: [
                        terminal.id: "codex",
                        secondTerminal.id: "zsh",
                    ]
                ),
            ],
            terminalTitle: "Terminal",
            browserTitle: "Browser",
            localizer: MyTTYLocalizer(language: .english)
        )

        #expect(items.map(\.paneID) == [
            terminal.id,
            browser.id,
            secondTerminal.id,
        ])
        #expect(items[0].windowID == windowID)
        #expect(items[0].tabID == firstTab.id)
        #expect(items[0].tabTitle == "Project")
        #expect(items[0].command == "codex")
        #expect(items[0].location == "/Users/example/project")
        #expect(items[0].kind == .terminal)
        #expect(!items[0].isActive)
        #expect(items[1].command == "Browser")
        #expect(items[1].location == "https://example.com/docs")
        #expect(items[1].kind == .browser)
        #expect(items[1].isActive)
        #expect(items[2].command == "zsh")
        #expect(items[2].tabTitle == "Notes")
        #expect(!items[2].isActive)
    }

    @Test("uses safe fallback labels and command basenames")
    func fallbacks() {
        let terminal = TerminalSurfaceState(
            workingDirectory: URL(fileURLWithPath: "/", isDirectory: true)
        )
        let tab = TabSession(initialSurface: terminal, pinnedTitle: nil)
        let session = WindowSession(
            frame: WindowFrame(x: 0, y: 0, width: 900, height: 600),
            tabs: [tab],
            selectedTabID: tab.id
        )

        let items = PaneListPresentation.items(
            snapshots: [
                PaneListWindowSnapshot(
                    session: session,
                    commandsByPane: [:]
                ),
            ],
            terminalTitle: "Terminal",
            browserTitle: "Browser",
            localizer: MyTTYLocalizer(language: .english)
        )

        #expect(items[0].command == "Terminal")
        #expect(items[0].location == "/")
        #expect(
            TerminalAgentProcessDetector.commandName(
                executablePath: "/opt/homebrew/bin/fish"
            ) == "fish"
        )
        #expect(
            TerminalAgentProcessDetector.commandName(executablePath: "")
                == nil
        )
    }

    @Test("shows an agent name instead of its launcher command")
    func agentCommandName() {
        #expect(
            PaneListPresentation.commandName(
                executableName: "node",
                provider: .codex
            ) == "Codex"
        )
        #expect(
            PaneListPresentation.commandName(
                executableName: "claude",
                provider: .claudeCode
            ) == "Claude Code"
        )
        #expect(
            PaneListPresentation.commandName(
                executableName: "zsh",
                provider: nil
            ) == "zsh"
        )
    }

    @Test("centers a compact pane list in the active screen")
    @MainActor
    func windowPlacement() throws {
        let frame = PaneListWindowPlacement.centeredFrame(
            windowSize: NSSize(width: 540, height: 400),
            visibleFrame: NSRect(x: 100, y: 50, width: 1400, height: 900)
        )
        let controller = PaneListWindowController(onFocus: { _ in })
        let window = try #require(controller.window)

        #expect(frame.origin.x == 530)
        #expect(frame.origin.y == 300)
        #expect(window.frame.width == 540)
    }

    @Test("selects clicked panes and moves selection with cursor keys")
    @MainActor
    func selectionInteraction() {
        let first = paneItem(command: "zsh")
        let second = paneItem(command: "Codex")
        let third = paneItem(command: "Claude Code")
        let model = PaneListModel()
        model.items = [first, second, third]
        model.selectedID = first.id

        model.select(second)
        #expect(model.selectedID == second.id)

        model.moveSelection(.next)
        #expect(model.selectedID == third.id)

        model.moveSelection(.next)
        #expect(model.selectedID == third.id)

        model.moveSelection(.previous)
        #expect(model.selectedID == second.id)
    }

    @Test("activates a clicked pane without waiting for a second click")
    @MainActor
    func clickActivation() {
        let pane = paneItem(command: "Codex")
        let model = PaneListModel()
        var dismissed = false
        var focusedItem: PaneListItem?
        model.onDismiss = { dismissed = true }
        model.onFocus = { focusedItem = $0 }

        model.activate(pane)

        #expect(model.selectedID == pane.id)
        #expect(dismissed)
        #expect(focusedItem == pane)
    }

    @Test("maps unmodified vertical cursor keys to pane navigation")
    func keyboardNavigation() {
        #expect(
            PaneListKeyboardNavigation.direction(
                forKeyCode: 126,
                modifierFlags: []
            ) == .previous
        )
        #expect(
            PaneListKeyboardNavigation.direction(
                forKeyCode: 125,
                modifierFlags: []
            ) == .next
        )
        #expect(
            PaneListKeyboardNavigation.direction(
                forKeyCode: 125,
                modifierFlags: [.command]
            ) == nil
        )
        #expect(
            PaneListKeyboardNavigation.direction(
                forKeyCode: 36,
                modifierFlags: []
            ) == nil
        )
    }

    private func paneItem(command: String) -> PaneListItem {
        PaneListItem(
            windowID: WindowID(),
            tabID: TabID(),
            paneID: TerminalSurfaceID(),
            tabTitle: "Tab",
            command: command,
            location: "/tmp",
            kind: .terminal,
            isActive: false
        )
    }
}
