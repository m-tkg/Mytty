import GhosttyKit
import Testing

@testable import GhosttyAdapter

@Suite("Ghostty surface input policy")
struct GhosttySurfaceInputPolicyTests {
    @Test("clears IME preedit before delivering committed text")
    func committedTextPlan() {
        let accumulated = GhosttySurfaceView.textCommitPlan(
            hadMarkedText: true,
            isAccumulatingKeyEvent: true
        )
        #expect(accumulated.clearsMarkedText)
        #expect(accumulated.delivery == .accumulator)

        let asynchronousCommit = GhosttySurfaceView.textCommitPlan(
            hadMarkedText: true,
            isAccumulatingKeyEvent: false
        )
        #expect(asynchronousCommit.clearsMarkedText)
        #expect(asynchronousCommit.delivery == .committedPreedit)

        let directText = GhosttySurfaceView.textCommitPlan(
            hadMarkedText: false,
            isAccumulatingKeyEvent: false
        )
        #expect(directText.clearsMarkedText)
        #expect(directText.delivery == .directText)
    }

    @Test("keeps C0 control input inside an active IME composition")
    func suppressesComposingControlInput() {
        #expect(
            GhosttySurfaceView.shouldSuppressComposingControlInput(
                "\n",
                composing: true
            )
        )
        #expect(
            GhosttySurfaceView.shouldSuppressComposingControlInput(
                "\u{0B}",
                composing: true
            )
        )
    }

    @Test("preserves normal terminal input")
    func preservesNormalInput() {
        #expect(
            !GhosttySurfaceView.shouldSuppressComposingControlInput(
                "\n",
                composing: false
            )
        )
        #expect(
            !GhosttySurfaceView.shouldSuppressComposingControlInput(
                "j",
                composing: true
            )
        )
        #expect(
            !GhosttySurfaceView.shouldSuppressComposingControlInput(
                "\n\u{0B}",
                composing: true
            )
        )
    }

    @Test("offers standard text actions for a terminal selection")
    func contextMenuActions() {
        #expect(
            GhosttySurfaceView.contextMenuActions(selectionText: "hello")
                == [
                    .lookUp,
                    .searchWeb,
                    .separator,
                    .copy,
                    .paste,
                    .separator,
                    .selectAll,
                    .separator,
                    .share,
                    .services,
                    .separator,
                    .closePane,
                ]
        )
        #expect(
            GhosttySurfaceView.contextMenuActions(selectionText: nil)
                == [.paste, .separator, .selectAll, .separator, .closePane]
        )
        #expect(
            GhosttySurfaceView.contextMenuActions(selectionText: " \n")
                == [
                    .copy, .paste, .separator, .selectAll,
                    .separator, .closePane,
                ]
        )
    }

    @Test("formats selected terminal text for native menu titles")
    func contextMenuSelectionPreview() {
        #expect(
            GhosttySurfaceView.contextMenuSelectionPreview(
                "  first\nsecond\tthird  "
            ) == "first second third"
        )
        #expect(
            GhosttySurfaceView.contextMenuSelectionPreview(
                String(repeating: "a", count: 60)
            ) == String(repeating: "a", count: 39) + "…"
        )
    }

    @Test("builds a Google search URL without losing selected text")
    func contextMenuSearchURL() {
        #expect(
            GhosttySurfaceView.contextMenuSearchURL(for: "hello world")?
                .absoluteString
                == "https://www.google.com/search?q=hello%20world"
        )
    }

    @Test("adds shift to command mouse events while a TUI captures the mouse")
    func commandMouseModsBypassMouseCapture() {
        let command = GHOSTTY_MODS_SUPER
        let bypassed = GhosttySurfaceView.mouseEventMods(
            command,
            mouseCaptured: true
        )
        #expect(
            bypassed.rawValue
                == GHOSTTY_MODS_SUPER.rawValue | GHOSTTY_MODS_SHIFT.rawValue
        )

        let commandOption = ghostty_input_mods_e(
            GHOSTTY_MODS_SUPER.rawValue | GHOSTTY_MODS_ALT.rawValue
        )
        #expect(
            GhosttySurfaceView.mouseEventMods(
                commandOption,
                mouseCaptured: true
            ).rawValue
                == commandOption.rawValue | GHOSTTY_MODS_SHIFT.rawValue
        )
    }

    @Test("leaves mouse mods alone without capture or without command")
    func mouseModsUnchangedOutsideCaptureBypass() {
        let command = GHOSTTY_MODS_SUPER
        #expect(
            GhosttySurfaceView.mouseEventMods(
                command,
                mouseCaptured: false
            ).rawValue == command.rawValue
        )

        let plain = GHOSTTY_MODS_NONE
        #expect(
            GhosttySurfaceView.mouseEventMods(
                plain,
                mouseCaptured: true
            ).rawValue == plain.rawValue
        )

        let shiftCommand = ghostty_input_mods_e(
            GHOSTTY_MODS_SUPER.rawValue | GHOSTTY_MODS_SHIFT.rawValue
        )
        #expect(
            GhosttySurfaceView.mouseEventMods(
                shiftCommand,
                mouseCaptured: true
            ).rawValue == shiftCommand.rawValue
        )
    }
}
