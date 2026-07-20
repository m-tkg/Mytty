import AppKit
import Foundation
import Testing

@testable import MyTTYApp

@Suite("Terminal autocomplete")
struct TerminalAutocompleteTests {
    @Test("suggests entering a directory after mkdir succeeds")
    func mkdirSuggestion() {
        var session = TerminalAutocompleteSession()

        #expect(session.handle(.text("mkdir aaa")) == .hide)
        #expect(session.handle(.submit) == .hide)
        #expect(
            session.commandFinished(exitCode: 0, reportedCommand: nil)
                == .show(
                    TerminalAutocompleteSuggestion(
                        displayText: "cd aaa",
                        insertionText: "cd aaa"
                    )
                )
        )
        #expect(session.handle(.accept) == .insert("cd aaa"))
    }

    @Test("supports mkdir parents and rejects ambiguous operands")
    func safeMkdirSuggestions() {
        #expect(
            TerminalAutocompleteEngine.nextCommand(
                afterSuccessfulCommand: "mkdir -p Sources/Feature"
            ) == "cd Sources/Feature"
        )
        #expect(
            TerminalAutocompleteEngine.nextCommand(
                afterSuccessfulCommand: "mkdir one two"
            ) == nil
        )
        #expect(
            TerminalAutocompleteEngine.nextCommand(
                afterSuccessfulCommand: "mkdir 'private notes'"
            ) == nil
        )
    }

    @Test("does not learn from failed commands")
    func failedCommand() {
        var session = TerminalAutocompleteSession()

        _ = session.handle(.text("mkdir blocked"))
        _ = session.handle(.submit)

        #expect(
            session.commandFinished(exitCode: 1, reportedCommand: nil)
                == .hide
        )
        #expect(session.successfulCommands.isEmpty)
    }

    @Test("another key dismisses a next-command suggestion")
    func dismissSuggestion() {
        var session = TerminalAutocompleteSession()

        _ = session.handle(.text("mkdir aaa"))
        _ = session.handle(.submit)
        _ = session.commandFinished(exitCode: 0, reportedCommand: nil)

        #expect(session.handle(.text("l")) == .hide)
        #expect(session.currentInput == "l")
        #expect(session.handle(.accept) == .hide)
    }

    @Test("completes a successful command from the current session")
    func currentSessionHistory() {
        var session = TerminalAutocompleteSession()

        _ = session.handle(.text("git status --short"))
        _ = session.handle(.submit)
        _ = session.commandFinished(exitCode: 0, reportedCommand: nil)

        #expect(
            session.handle(.text("git s"))
                == .show(
                    TerminalAutocompleteSuggestion(
                        displayText: "tatus --short",
                        insertionText: "tatus --short"
                    )
                )
        )
        #expect(session.handle(.accept) == .insert("tatus --short"))
        #expect(session.currentInput == "git status --short")
    }

    @Test("uses the shell-reported command when keyboard editing was opaque")
    func reportedCommandFallback() {
        var session = TerminalAutocompleteSession()

        _ = session.handle(.editingNavigation)
        _ = session.handle(.submit)

        #expect(
            session.commandFinished(
                exitCode: 0,
                reportedCommand: "mkdir restored"
            ) == .show(
                TerminalAutocompleteSuggestion(
                    displayText: "cd restored",
                    insertionText: "cd restored"
                )
            )
        )
    }

    @Test("maps terminal keys without stealing application shortcuts")
    @MainActor
    func keyMapping() throws {
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(keyCode: 48, characters: "\t"),
                hasMarkedText: false
            ) == .accept
        )
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(keyCode: 51, characters: "\u{7F}"),
                hasMarkedText: false
            ) == .deleteBackward
        )
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(keyCode: 36, characters: "\r"),
                hasMarkedText: false
            ) == .submit
        )
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(keyCode: 123, characters: ""),
                hasMarkedText: false
            ) == .editingNavigation
        )
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(keyCode: 0, characters: "a"),
                hasMarkedText: true
            ) == .cancel
        )
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(
                    keyCode: 0,
                    characters: "a",
                    modifiers: .command
                ),
                hasMarkedText: false
            ) == nil
        )
        #expect(
            TerminalAutocompleteEventMapper.input(
                for: try keyEvent(
                    keyCode: 8,
                    characters: "\u{3}",
                    modifiers: .control
                ),
                hasMarkedText: false
            ) == .resetLine
        )
    }

    @Test("recovers autocomplete tracking after Ctrl-C clears the line")
    func resetLine() {
        var session = TerminalAutocompleteSession()
        _ = session.handle(.text("unfinished"))
        _ = session.handle(.editingNavigation)
        _ = session.handle(.resetLine)
        _ = session.handle(.text("mkdir recovered"))
        _ = session.handle(.submit)

        #expect(
            session.commandFinished(exitCode: 0, reportedCommand: nil)
                == .show(
                    TerminalAutocompleteSuggestion(
                        displayText: "cd recovered",
                        insertionText: "cd recovered"
                    )
                )
        )
    }

    @MainActor
    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
