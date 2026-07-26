import Foundation

/// How many terminal cells a character occupies, so a client drawing a
/// mirrored screen on a fixed grid advances by the same amount the host's
/// terminal did. Without this, one CJK character or emoji shifts the rest
/// of the line by a cell and the whole screen shears.
///
/// This is the usual `wcwidth` classification, kept deliberately small:
/// combining marks and other zero-width scalars take no cell, East Asian
/// Wide/Fullwidth and emoji take two, everything else takes one. Control
/// characters never reach here — the host strips them while encoding the
/// screen.
public enum RemoteCellWidth {
    /// Cells occupied by a whole string.
    public static func displayWidth(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + width(of: $1) }
    }

    /// Cells occupied by one grapheme cluster. A cluster is measured by its
    /// first non-zero-width scalar so that, say, a base letter followed by
    /// a combining accent still takes exactly one cell.
    public static func displayWidth(of character: Character) -> Int {
        for scalar in character.unicodeScalars {
            let width = width(of: scalar)
            if width > 0 { return width }
        }
        return 0
    }

    private static func width(of scalar: Unicode.Scalar) -> Int {
        if isZeroWidth(scalar) { return 0 }
        if isWide(scalar) { return 2 }
        return 1
    }

    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        // Combining marks, variation selectors, and the zero-width joiner
        // all render on top of (or between) neighbouring cells.
        switch scalar.value {
        case 0x0300...0x036F,
             0x0483...0x0489,
             0x0591...0x05BD,
             0x0610...0x061A,
             0x064B...0x065F,
             0x0670,
             0x06D6...0x06DC,
             0x0E31, 0x0E34...0x0E3A, 0x0E47...0x0E4E,
             0x200B...0x200F,
             0x20D0...0x20F0,
             0xFE00...0xFE0F,
             0xFE20...0xFE2F,
             0xE0100...0xE01EF:
            return true
        default:
            return false
        }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Hangul Jamo initial consonants.
        case 0x1100...0x115F,
             // Watch/hourglass symbols that terminals render double-width.
             0x231A...0x231B,
             0x2329...0x232A,
             0x23E9...0x23EC, 0x23F0, 0x23F3,
             0x25FD...0x25FE,
             0x2614...0x2615,
             0x2648...0x2653,
             0x267F, 0x2693, 0x26A1,
             0x26AA...0x26AB,
             0x26BD...0x26BE,
             0x26C4...0x26C5,
             0x26CE, 0x26D4, 0x26EA,
             0x26F2...0x26F3, 0x26F5, 0x26FA, 0x26FD,
             0x2705, 0x270A...0x270B, 0x2728, 0x274C, 0x274E,
             0x2753...0x2755, 0x2757,
             0x2795...0x2797, 0x27B0, 0x27BF,
             0x2B1B...0x2B1C, 0x2B50, 0x2B55,
             // CJK radicals through the Hangul syllables block.
             0x2E80...0x303E,
             0x3041...0x33FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xA000...0xA4CF,
             0xA960...0xA97F,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             // Supplementary planes: emoji and the CJK extensions.
             0x1F004, 0x1F0CF,
             0x1F18E,
             0x1F191...0x1F19A,
             0x1F200...0x1F320,
             0x1F32D...0x1F335,
             0x1F337...0x1F37C,
             0x1F37E...0x1F393,
             0x1F3A0...0x1F3CA,
             0x1F3CF...0x1F3D3,
             0x1F3E0...0x1F3F0,
             0x1F3F4, 0x1F3F8...0x1F43E, 0x1F440,
             0x1F442...0x1F4FC,
             0x1F4FF...0x1F53D,
             0x1F54B...0x1F54E,
             0x1F550...0x1F567,
             0x1F57A, 0x1F595...0x1F596, 0x1F5A4,
             0x1F5FB...0x1F64F,
             0x1F680...0x1F6C5,
             0x1F6CC,
             0x1F6D0...0x1F6D2,
             0x1F6EB...0x1F6EC,
             0x1F6F4...0x1F6FC,
             0x1F7E0...0x1F7EB,
             0x1F90C...0x1F9FF,
             0x1FA70...0x1FAFF,
             0x20000...0x2FFFD,
             0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
