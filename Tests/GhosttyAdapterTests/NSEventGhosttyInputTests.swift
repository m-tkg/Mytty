import AppKit
import GhosttyKit
import Testing

@testable import GhosttyAdapter

@Suite("NSEvent Ghostty input")
struct NSEventGhosttyInputTests {
    /// kVK_ANSI_E
    private static let keyCodeE: UInt16 = 14

    private func keyDown(
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        charactersIgnoringModifiers: String
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isARepeat: false,
                keyCode: Self.keyCodeE
            )
        )
    }

    @Test("drops shift from the unshifted codepoint")
    func unshiftedCodepointIgnoresShift() throws {
        // AppKit reports "E" for charactersIgnoringModifiers on a real
        // Ctrl+Shift+E, but the kitty keyboard protocol wants the codepoint
        // the key produces with no modifiers at all — otherwise the surface
        // emits `CSI 69;6u` and apps never match their `ctrl+shift+e` binding.
        let event = try keyDown(
            modifierFlags: [.control, .shift],
            characters: "\u{05}",
            charactersIgnoringModifiers: "E"
        )
        let input = event.ghosttyInput(action: GHOSTTY_ACTION_PRESS)
        #expect(input.unshifted_codepoint == 0x65)
    }

    @Test("keeps the unshifted codepoint without shift")
    func unshiftedCodepointWithoutShift() throws {
        let event = try keyDown(
            modifierFlags: [.control],
            characters: "\u{05}",
            charactersIgnoringModifiers: "e"
        )
        let input = event.ghosttyInput(action: GHOSTTY_ACTION_PRESS)
        #expect(input.unshifted_codepoint == 0x65)
    }
}
