import AppKit
import GhosttyAdapter
import MyTTYCore

extension TerminalAppearance {
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    func ghosttyColorScheme(
        effectiveAppearance: NSAppearance
    ) -> GhosttyColorScheme {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                == .darkAqua ? .dark : .light
        }
    }
}

extension NSColor {
    /// Builds a color from an `RRGGBB` string; unparsable input yields black,
    /// matching how preference hex values are stored (no alpha channel).
    convenience init(hexRGB: String) {
        let value = UInt64(hexRGB, radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexRGB: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
