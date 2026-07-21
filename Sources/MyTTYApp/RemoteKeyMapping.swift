import AppKit

/// Translates a `RemoteMessage.sendKey` payload into the macOS virtual
/// key code and characters needed to synthesize a real key event.
enum RemoteKeyMapping {
    struct KeyEvent: Equatable {
        let keyCode: UInt16
        let characters: String
        let modifierFlags: NSEvent.ModifierFlags

        static func == (lhs: KeyEvent, rhs: KeyEvent) -> Bool {
            lhs.keyCode == rhs.keyCode
                && lhs.characters == rhs.characters
                && lhs.modifierFlags == rhs.modifierFlags
        }
    }

    /// ANSI virtual key codes plus the AppKit function-key characters
    /// (`NSUpArrowFunctionKey` and friends in the F700 range) that real
    /// hardware events carry.
    private static let namedKeys: [String: (UInt16, String)] = [
        "escape": (53, "\u{1B}"),
        "tab": (48, "\t"),
        "return": (36, "\r"),
        // "return" is the canonical macOS name and what NSEvent reports,
        // but "enter" is the more natural first guess for anyone typing a
        // `send-key` command by hand, so accept it as an alias.
        "enter": (36, "\r"),
        "delete": (51, "\u{7F}"),
        "space": (49, " "),
        "up": (126, "\u{F700}"),
        "down": (125, "\u{F701}"),
        "left": (123, "\u{F702}"),
        "right": (124, "\u{F703}"),
        "f1": (122, "\u{F704}"),
        "f2": (120, "\u{F705}"),
        "f3": (99, "\u{F706}"),
        "f4": (118, "\u{F707}"),
        "f5": (96, "\u{F708}"),
        "f6": (97, "\u{F709}"),
        "f7": (98, "\u{F70A}"),
        "f8": (100, "\u{F70B}"),
        "f9": (101, "\u{F70C}"),
        "f10": (109, "\u{F70D}"),
        "f11": (103, "\u{F70E}"),
        "f12": (111, "\u{F70F}"),
    ]

    /// ANSI-layout virtual key codes for characters that can arrive as
    /// modifier combos (Ctrl+C and the like).
    private static let characterKeys: [Character: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
        "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25,
        "[": 33, "]": 30, "\\": 42, "-": 27, "=": 24, ";": 41,
        "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    static func event(key: String, modifiers: [String]) -> KeyEvent? {
        let flags = modifierFlags(from: modifiers)
        if let (keyCode, characters) = namedKeys[key.lowercased()] {
            return KeyEvent(
                keyCode: keyCode,
                characters: characters,
                modifierFlags: flags
            )
        }
        guard key.count == 1, let character = key.first,
              let keyCode = characterKeys[Character(key.lowercased())]
        else { return nil }
        return KeyEvent(
            keyCode: keyCode,
            characters: String(character),
            modifierFlags: flags
        )
    }

    private static func modifierFlags(
        from modifiers: [String]
    ) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case "shift": flags.insert(.shift)
            case "control": flags.insert(.control)
            case "option": flags.insert(.option)
            case "command": flags.insert(.command)
            default: break
            }
        }
        return flags
    }
}
