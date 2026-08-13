import AppKit
import GhosttyKit

extension NSEvent {
    func ghosttyInput(action: ghostty_input_action_e) -> ghostty_input_key_s {
        var input = ghostty_input_key_s()
        input.action = action
        input.mods = modifierFlags.ghosttyMods
        input.consumed_mods = modifierFlags
            .subtracting([.control, .command])
            .ghosttyMods
        input.keycode = UInt32(keyCode)
        // The kitty keyboard protocol reports the codepoint the key produces
        // with *no* modifiers at all, so Ctrl+Shift+E has to encode as
        // `CSI 101;6u` ("e"), not `CSI 69;6u` ("E"). AppKit's
        // `charactersIgnoringModifiers` keeps shift applied, which would
        // encode the shifted letter and leave apps unable to match their
        // `ctrl+shift+<letter>` bindings. `characters(byApplyingModifiers:)`
        // re-translates from the keycode instead, so shift is dropped too.
        // Synthesized events (`sendKeyPress`) carry no layout to translate
        // from, hence the fallback.
        input.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp {
            let unshifted = characters(byApplyingModifiers: [])
                ?? charactersIgnoringModifiers
            input.unshifted_codepoint = unshifted?
                .unicodeScalars
                .first?
                .value ?? 0
        }
        return input
    }

    var ghosttyText: String? {
        guard let characters else { return nil }
        guard characters.count == 1,
              let scalar = characters.unicodeScalars.first
        else { return characters }
        if scalar.value < 0x20 {
            return charactersIgnoringModifiers
        }
        if (0xF700...0xF8FF).contains(scalar.value) {
            return nil
        }
        return characters
    }
}

extension NSEvent.ModifierFlags {
    var ghosttyMods: ghostty_input_mods_e {
        var value = GHOSTTY_MODS_NONE.rawValue
        if contains(.shift) { value |= GHOSTTY_MODS_SHIFT.rawValue }
        if contains(.control) { value |= GHOSTTY_MODS_CTRL.rawValue }
        if contains(.option) { value |= GHOSTTY_MODS_ALT.rawValue }
        if contains(.command) { value |= GHOSTTY_MODS_SUPER.rawValue }
        if contains(.capsLock) { value |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(value)
    }
}

extension NSEvent.Phase {
    var ghosttyMomentum: Int {
        if contains(.began) { return 1 }
        if contains(.stationary) { return 2 }
        if contains(.changed) { return 3 }
        if contains(.ended) { return 4 }
        if contains(.cancelled) { return 5 }
        if contains(.mayBegin) { return 6 }
        return 0
    }
}
