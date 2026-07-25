import Carbon.HIToolbox
import MyTTYCore

/// Converts a `MyTTYKeyBinding` into the Carbon virtual key code and
/// modifier flags `RegisterEventHotKey` expects (`GlobalHotKeyRegistrar.swift`).
/// Same layer as `KeyBindingRecorderButton.appKitKeyEquivalent`
/// (`KeyBindingRecorderButton.swift:129-157`) -- a pure lookup table -- but
/// targets Carbon's key-code space instead of an `NSEvent`/menu key
/// equivalent, and covers `MyTTYKeyBinding`'s named keys
/// (`KeyBinding.swift:292-299`) plus every letter and digit.
enum CarbonKeyCode {
    /// The `(keyCode, modifierFlags)` pair for `binding`, or `nil` if the
    /// binding's key has no Carbon virtual key code (shouldn't happen for
    /// any key `MyTTYKeyBinding` actually accepts, but this stays a lookup
    /// rather than a crash so a future key stays a registration failure
    /// instead of a runtime trap).
    static func hotKey(
        for binding: MyTTYKeyBinding
    ) -> (keyCode: UInt32, modifierFlags: UInt32)? {
        guard let keyCode = virtualKeyCode(for: binding.key) else {
            return nil
        }
        return (keyCode, modifierFlags(for: binding.modifiers))
    }

    static func virtualKeyCode(for key: String) -> UInt32? {
        namedKeyCodes[key] ?? characterKeyCodes[key]
    }

    static func modifierFlags(
        for modifiers: Set<MyTTYKeyModifier>
    ) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// Named keys, mirroring `MyTTYKeyBinding`'s own table.
    private static let namedKeyCodes: [String: UInt32] = [
        "left": UInt32(kVK_LeftArrow),
        "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow),
        "down": UInt32(kVK_DownArrow),
        "return": UInt32(kVK_Return),
        "tab": UInt32(kVK_Tab),
        "space": UInt32(kVK_Space),
        "escape": UInt32(kVK_Escape),
        "home": UInt32(kVK_Home),
        "end": UInt32(kVK_End),
        "page-up": UInt32(kVK_PageUp),
        "page-down": UInt32(kVK_PageDown),
        "comma": UInt32(kVK_ANSI_Comma),
        "period": UInt32(kVK_ANSI_Period),
        "slash": UInt32(kVK_ANSI_Slash),
        "semicolon": UInt32(kVK_ANSI_Semicolon),
        "quote": UInt32(kVK_ANSI_Quote),
        "left-bracket": UInt32(kVK_ANSI_LeftBracket),
        "right-bracket": UInt32(kVK_ANSI_RightBracket),
        "backslash": UInt32(kVK_ANSI_Backslash),
        "backtick": UInt32(kVK_ANSI_Grave),
        "minus": UInt32(kVK_ANSI_Minus),
        "equal": UInt32(kVK_ANSI_Equal),
        // No ANSI code of its own on a US layout -- it's shift+equal, so it
        // shares equal's virtual key code.
        "plus": UInt32(kVK_ANSI_Equal),
    ]

    /// Letters and digits, keyed by the lowercase character
    /// `MyTTYKeyBinding.key` stores.
    private static let characterKeyCodes: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
    ]
}
